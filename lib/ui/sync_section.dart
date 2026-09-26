import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sync/identity_store.dart';
import '../data/sync/sync_service.dart';
import '../data/sync/adb_carrier.dart';
import '../data/sync/firewall_probe.dart';
import '../data/sync/socket_transport.dart';
import '../domain/sync/firewall.dart';
import '../domain/sync/device_identity.dart';
import '../domain/sync/link_mode.dart';
import '../domain/sync/short_code.dart';
import '../domain/sync/exchange.dart';
import '../domain/sync/pairing.dart';
import '../domain/sync/lan_address.dart';
import '../domain/sync/scope.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'pack_section.dart';
import 'discovery_providers.dart';
import '../domain/sync/discovery.dart';
import 'sync_identity.dart';
import 'theme.dart';

/// Builds the service the screen talks to.
///
/// **A factory rather than the service itself, because the service needs the open cellar and the
/// cellar is asynchronous.** `cellarProvider` hands back a `Cellar` once the log has been read, and
/// a provider that returned a `SocketSyncService` directly would be rebuilt every time an event was
/// recorded -- throwing away a bound listener and an exchange in flight along with it, which a
/// reader would experience as a sync that silently stops working the moment they pour something.
///
/// Overridden in widget tests with a fake, which is the point of it being a provider.
typedef SyncServiceFactory = SyncService Function(SyncSource source);

final syncServiceFactoryProvider = Provider<SyncServiceFactory>(
  (ref) => (source) => SocketSyncService(source: source),
);

/// Which of the four things this screen can be doing.
enum SyncPhase {
  /// Nothing has been started.
  idle,

  /// A code is on screen and a listener is open.
  hosting,

  /// A connection is being made, or an exchange is running.
  working,

  /// There is a result, successful or not.
  done,
}

/// Everything the section draws, in one value.
final class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.ticket,
    this.outcome,
    this.codeRejected = false,
    this.scope = const SyncScope.everything(),
    this.comparingCode,
  });

  final SyncPhase phase;

  /// The code being shown, while hosting.
  final PairingTicket? ticket;

  /// What the last exchange did, when there was one.
  final ExchangeOutcome? outcome;

  /// Whether the reader typed something that is not one of our codes.
  ///
  /// Separate from [outcome], because there is no exchange to report on: the string failed before
  /// any connection was attempted, and the reader can fix it by retyping.
  final bool codeRejected;

  /// **What this device is willing to hand over** -- section 10.3's last promise.
  final SyncScope scope;

  /// **The six digits on the screen, while a person is comparing two devices.**
  ///
  /// Non-null means a handshake has completed and nothing has been exchanged: the session is stopped on a
  /// human decision, which is what the owner chose to offer (*"两条都给，让读者选"*). The digits are the same on
  /// both screens when nobody interfered, and different when somebody did -- see `domain/sync/short_code.dart`.
  final String? comparingCode;
}

/// Holds the one sync this device is doing.
///
/// **A `Notifier` and not a `FutureProvider`, because a sync is an action rather than a value.** A
/// reader presses a button, something happens over seconds, and the screen has to say what is
/// happening in between -- which is state a future cannot describe without being wrapped in one
/// anyway.
final class SyncController extends Notifier<SyncState> {
  SyncService? _service;
  SyncScope _scope = const SyncScope.everything();

  /// **Whether the reader chose to add this device by comparing screens**, for the session in flight.
  ///
  /// It is a decision about *this* meeting rather than a setting: somebody who compared numbers once has not
  /// asked to compare them every time, so it is cleared when a session ends.
  bool _comparisonWanted = false;

  /// **Holds the one comparison this device is doing.**
  ///
  /// The gate in `runExchange` awaits this future, so the exchange is genuinely stopped until a person presses
  /// a button -- not "asked and assumed". Completing it twice is harmless: the gate reads the first answer and
  /// the session is over either way, which is the one-shot rule (`ShortCode.isOneShot`) held by construction.
  Completer<bool>? _comparison;

  /// Whether the listener a neighbour's tap arrives at is open, and which generation of the accept loop owns it.
  ///
  /// **A generation rather than a flag alone, because the loop outlives a single socket.** A tap that arrives,
  /// is declined or fails, and leaves the loop waiting again must not be confused with a listener that was
  /// closed while the request was in flight -- the second is the compare screen taking over, and its outcome has
  /// to be shown rather than swallowed.
  bool _reachable = false;
  int _acceptGeneration = 0;

  /// **Whether the screen still wants to be reachable**, which is not the same question as whether the socket is
  /// open: the bind is asynchronous, so a screen that is closed while it is in flight would otherwise leave a
  /// listener running with nobody to close it and an announcement naming a port the reader is no longer offering.
  bool _requestsWanted = false;

  /// This device's own key while the listener is open, so the accept loop offers the same identity the
  /// announcement is advertising under.
  DeviceIdentity? _requestIdentity;

  /// **The two listener operations run one after another, and that is a defect repaired rather than tidiness.**
  ///
  /// Opening and closing are both asynchronous, so a screen that is scrolled away and back can interleave them:
  /// the old screen's `closeForRequests` was already in flight when the new screen's `openForRequests` bound a
  /// fresh socket, and the late close then closed **that** one. Observed on a phone -- after scrolling the sync
  /// section out of view and back, 附近的设备现在可以点到这台机器 was gone for the rest of the session, and a
  /// neighbour's tap would have timed out against a device that still believed it was reachable. A chain serialises
  /// the calls in the order they were made, so the last one to be *asked for* is the one that holds the socket.
  Future<void> _listenerChain = Future<void>.value();

  Future<T> _serialised<T>(Future<T> Function() action) {
    final result = _listenerChain.then((_) => action());
    // The chain must survive a failed step, or one bind error would block every later attempt.
    _listenerChain = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  /// **Opens the listener a neighbour's tap arrives at, and answers with the port it holds** (§10.3.2).
  ///
  /// Called by the screen and not by a button, because the two are one promise: a device that is announcing itself
  /// is a device a tap can reach, and an announcement naming a port with no socket behind it is exactly the bug
  /// this replaces. It is idempotent, so a rebuild does not open a second listener on a second port -- the
  /// announcement would then be true of neither.
  Future<int?> openForRequests({
    required DeviceIdentity? identity,
    required Set<String> acceptedIdentities,
  }) => _serialised(() => _openForRequests(identity: identity, acceptedIdentities: acceptedIdentities));

  Future<int?> _openForRequests({
    required DeviceIdentity? identity,
    required Set<String> acceptedIdentities,
  }) async {
    if (_reachable && _listeningPort != null) return _listeningPort;
    _requestsWanted = true;
    final service = await _ensure();
    if (service == null) return null;
    try {
      final port = await service.openForRequests(
        identity: identity,
        acceptedIdentities: acceptedIdentities,
      );
      if (!_requestsWanted) {
        // The screen was closed while the socket was binding. Closed again here rather than left open: a listener
        // nobody is offering is precisely the stale announcement this work exists to remove.
        await service.closeForRequests();
        return null;
      }
      _reachable = true;
      _requestIdentity = identity;
      _listeningPort = port;
      // **Published, because the announcement has to carry it.** A device that is listening on a port nobody is
      // told about is a device a tap cannot reach; see `reachablePortProvider`.
      ref.read(reachablePortProvider.notifier).publish(port);
      _acceptGeneration++;
      unawaited(_acceptRequests(service, _acceptGeneration));
      return port;
    } on Object catch (error) {
      state = SyncState(
        phase: SyncPhase.done,
        outcome: ExchangeOutcome(
          merged: 0,
          sent: 0,
          failure: 'could not open the listener a tap arrives at: $error',
        ),
        scope: _scope,
      );
      return null;
    }
  }

  /// The port this device is reachable on, or null when it is not.
  int? _listeningPort;

  /// Closes that listener. The screen is no longer being looked at, so nobody can see this device either.
  ///
  /// **Serialised with [openForRequests]**, so a close that arrives late -- the screen it belonged to is already
  /// gone -- cannot take away the socket a newer screen has just bound.
  Future<void> closeForRequests() => _serialised(_closeForRequests);

  Future<void> _closeForRequests() async {
    _requestsWanted = false;
    if (!_reachable && _listeningPort == null) return;
    _reachable = false;
    _listeningPort = null;
    _acceptGeneration++;
    // Cleared before the socket is closed, so the announcement stops naming a port in the same turn the port
    // stops existing rather than three seconds later.
    ref.read(reachablePortProvider.notifier).publish(null);
    await _service?.closeForRequests();
  }

  /// **Waits for a neighbour's tap, one at a time, for as long as the listener is open.**
  ///
  /// The offer is the comparison gate: a device that proves a remembered key walks in on that key, and one that
  /// proves nothing gets as far as the six digits and no further (`runExchange` refuses an unproved peer unless
  /// a gate is passed, which is why the gate is the parameter here rather than a separate switch).
  Future<void> _acceptRequests(SyncService service, int generation) async {
    while (_reachable && generation == _acceptGeneration) {
      final outcome = await service.awaitRequest(
        identity: _requestIdentity,
        confirmComparison: _askToCompare,
      );
      // **A screen that is gone takes nothing with it, and must not throw on the way out.** A request can be in
      // flight when the reader leaves the tab; writing to a disposed notifier raises `UnmountedRefException`,
      // which is a crash caused by somebody leaving a screen rather than by anything being wrong.
      if (!ref.mounted) return;
      // **[defect, found by the owner] The outcome is taken before the loop asks whether it should stop.**
      // The order was the other way round, and the guard it used -- a generation counter -- changes for the
      // ordinary reason that the screen was scrolled away or the section rebuilt, not only for a real stop. So a
      // tap that *succeeded* could end with the peer forgotten and no result on the screen: the guard returned
      // before `_remember` and before the state was published. "The device was not remembered" is how it was
      // reported, and this is why.
      await _remember(
        outcome,
        // **The address the connection actually came from**, which is what 再同步一次 dials. An accepted
        // connection knows it; nothing else does.
        address: outcome.peerAddress.isEmpty ? null : outcome.peerAddress,
      );
      if (!ref.mounted) return;
      state = SyncState(phase: SyncPhase.done, outcome: outcome, scope: _scope);
      if (generation != _acceptGeneration) return;
      if (!_reachable) return;
      // A listener whose socket went away under it -- somebody pressed 显示配对码, which binds its own -- is not
      // a failure worth a message: the screen already says what is happening, and the next opening rebinds.
      if ((outcome.failure ?? '').contains('stopped listening')) return;
    }
  }

  /// **The tap in 附近的设备, once the reader has confirmed it** (§10.3.2, the owner's decision).
  ///
  /// Two meetings, one method, because the reader's confirmation box already told them which one this is:
  ///
  /// * **a device this machine has met** is reached with the key it learned, at the address the announcement
  ///   gave -- which is fresher than the address in the store, whose port changes every time that device starts
  ///   listening;
  /// * **a stranger** has nothing to be reached with, and there is no code to type, so the six digits on two
  ///   screens are the authentication. That is the same conclusion §10.3 already reached: a relay can forward a
  ///   code and cannot produce two identical transcripts.
  Future<void> joinNearby(DiscoveredDevice device) async {
    final service = await _ensure();
    if (service == null) return;
    final stored = _storedIdentity();
    // **The same spelling on both sides**, or a device this machine has met is asked for six digits as if it were
    // a stranger: the announcement's fingerprint is grouped and the store's is a digest.
    final trusted = (stored?.trusted ?? const <TrustedDevice>[]).where(
      (candidate) => DeviceIdentity.sameFingerprint(
        DeviceIdentity.fingerprintOf(candidate.publicKey),
        device.fingerprint,
      ),
    );
    final key = device.fingerprint.isEmpty
        ? ''
        : (trusted.isEmpty ? '' : trusted.first.publicKey);

    state = SyncState(phase: SyncPhase.working, scope: _scope);
    final outcome = await service.join(
      PairingTicket(
        host: device.address,
        port: device.port,
        token: '',
        name: device.name,
      ),
      identity: stored?.identity,
      // **No key means a stranger, and a stranger is asked to compare digits.** The alternative -- passing
      // nothing and letting the handshake through -- would be a first meeting that nothing authenticates.
      expectedIdentity: key,
      confirmComparison: key.isEmpty ? _askToCompare : null,
    );
    await _remember(
      outcome,
      address: '${device.address}:${device.port}',
      fallbackName: device.name,
    );
    state = SyncState(phase: SyncPhase.done, outcome: outcome, scope: _scope);
  }

  /// Called with the digits when a comparison is needed; the future is what the exchange waits on.
  Future<bool> _askToCompare(String shortCode) {
    final completer = Completer<bool>();
    _comparison = completer;
    state = SyncState(
      phase: SyncPhase.working,
      ticket: state.ticket,
      scope: _scope,
      comparingCode: shortCode,
    );
    return completer.future;
  }

  /// What the person said, and the only way a comparison ever finishes.
  ///
  /// **A mismatch gives the session up rather than retrying.** Six digits is about twenty bits: enough exactly
  /// once, and a retry button would hand an attacker as many attempts as they have patience for. Nothing here
  /// asks again -- the only way back is a new session, which means a new handshake and a different twenty bits.
  ///
  /// **[defect, found on a real phone] The screen has to change when the answer is taken.** It did not: agreeing
  /// completed the gate and left the same six digits and the same two buttons on screen, because the exchange
  /// does not finish until the *other* device's person has agreed too. So the one thing a reader sees after
  /// pressing the button is nothing, and "the button does not work" is the only reading available to them -- which
  /// is how it was reported, from a phone, in front of a comparison that was working exactly as designed.
  ///
  /// Agreeing therefore moves the screen off the question and into the working state, which is the truth: *this*
  /// device has answered and is waiting for the other screen. Refusing needs no state of its own -- the exchange
  /// ends at once with the reason, and the outcome says which of the two answers it was.
  void answerComparison({required bool agree}) {
    final completer = _comparison;
    _comparison = null;
    if (completer == null || completer.isCompleted) return;
    if (agree) {
      state = SyncState(phase: SyncPhase.working, ticket: state.ticket, scope: _scope);
    }
    completer.complete(agree);
  }

  /// Whether the reader has chosen the comparison for the next session.
  bool get comparisonWanted => _comparisonWanted;

  /// The reader picked the comparison: the next session asks them to look at two screens.
  ///
  /// **It sets the choice and leaves the phase alone.** The first version moved to `working`, which took the
  /// reader off the screen where the code field is -- so picking the comparison meant never being able to start
  /// anything. A toggle is not a step.
  void chooseComparison({required bool compare}) {
    _comparisonWanted = compare;
    // Re-emit with the same phase so the chips redraw; the section draws from `state`, not from a local field.
    state = SyncState(
      phase: state.phase,
      ticket: state.ticket,
      outcome: state.outcome,
      codeRejected: state.codeRejected,
      scope: _scope,
      comparingCode: state.comparingCode,
    );
  }

  @override
  SyncState build() {
    ref.onDispose(() => _service?.stop());
    return const SyncState();
  }

  /// The service, built once from whichever log is open and kept for the life of the notifier.
  ///
  /// **It awaits the cellar rather than reading it.** The first version read
  /// `cellarProvider.value`, which is null until the log has been read from disk -- and a button
  /// pressed in that window did *nothing at all*, silently, because the method returned early. A
  /// reader can press the button before the cellar finishes loading; it is a small file, but the
  /// window is real and the failure was a dead control with no message. Awaiting the future makes
  /// the press wait instead, which is what a person expects a button to do.
  ///
  /// A cellar that will not open is reported as a sync that failed, in the same place a refused
  /// connection is reported, rather than as an exception nobody catches.
  Future<SyncService?> _ensure() async {
    final existing = _service;
    if (existing != null) return existing;
    try {
      final cellar = await ref.read(cellarProvider.future);
      final source = _sourceFor(cellar);
      final built = ref.read(syncServiceFactoryProvider)(source);
      _service = built;
      return built;
    } on Object catch (error) {
      state = SyncState(
        phase: SyncPhase.done,
        outcome: ExchangeOutcome(merged: 0, sent: 0, failure: 'the cellar could not be opened: $error'),
      );
      return null;
    }
  }

  /// **The source an exchange reads through: the log, or the log seen through a scope.**
  ///
  /// Section 10.3 promises that a share can be limited to "which Bar" rather than the whole library,
  /// and a sync sends everything the other side is missing -- so without this, pairing with a friend's
  /// laptop hands over the cellar. `ScopedSyncSource` filters what this device *offers*; it does not
  /// filter what it accepts, because a scope is a statement about giving.
  SyncSource _sourceFor(Cellar cellar) => _scope.isEverything
      ? cellar.log
      : ScopedSyncSource(
          inner: cellar.log,
          scope: _scope,
          events: cellar.log.events,
        );

  /// Changes what a share will carry, and **drops the service so the next action rebuilds it**.
  ///
  /// The scope is decided when the exchange is built rather than checked per frame, so a service built
  /// under the old scope must not be reused: it would send the whole cellar while the screen said
  /// otherwise, which is the worst version of this feature.
  Future<void> setScope(SyncScope scope) async {
    if (scope.shelfId == _scope.shelfId) return;
    _scope = scope;
    await _service?.stop();
    _service = null;
    state = SyncState(
      phase: SyncPhase.done,
      outcome: state.outcome,
      scope: scope,
    );
  }

  /// Binds a listener, puts the code on screen, and waits for the peer that reads it.
  ///
  /// **The waiting is the same action as the showing, and that is deliberate.** The state moves to
  /// [SyncPhase.hosting] *before* the await, so the screen draws the code immediately and then sits
  /// there while the other device types it in; when the peer arrives the await returns and the same
  /// method writes the outcome. A separate "wait" button would ask the reader to confirm something
  /// they have already decided, and there is nothing else the code could be for.
  Future<void> startHosting({String? token}) async {
    final service = await _ensure();
    if (service == null) return;
    final stored = _storedIdentity();
    state = SyncState(phase: SyncPhase.working, scope: _scope);
    // **Every device this one has met is a way in without a code**, and the code stays a way in for
    // everybody else. A host cannot know which device is coming, so it accepts either proof.
    final ticket = await service.host(
      identity: stored?.identity,
      acceptedIdentities: {
        for (final device in stored?.trusted ?? const <TrustedDevice>[])
          device.publicKey,
      },
      // The reader's own token when they typed one, otherwise the generator's.
      token: token,
    );
    state = SyncState(phase: SyncPhase.hosting, ticket: ticket, scope: _scope);
    // **A remembered device needs no comparison**: its key is the authentication, and asking somebody to
    // compare numbers for a device they synced with last week would be ceremony. A brand-new device is exactly
    // the case this exists for.
    final compare = _comparisonWanted ? _askToCompare : null;
    final outcome = await service.awaitPeer(confirmComparison: compare);
    state = state.comparingCode == null
        ? state
        : SyncState(phase: SyncPhase.working, scope: _scope);
    await _remember(outcome, address: null);
    state = SyncState(phase: SyncPhase.done, outcome: outcome, scope: _scope);
  }

  /// Parses what the reader typed, and reaches the device it names.
  Future<void> join(String code) async {
    final ticket = PairingTicket.parse(code);
    if (ticket == null) {
      state = SyncState(phase: SyncPhase.done, codeRejected: true, scope: _scope);
      return;
    }
    final service = await _ensure();
    if (service == null) return;
    final stored = _storedIdentity();
    state = SyncState(phase: SyncPhase.working, scope: _scope);
    final compare = _comparisonWanted ? _askToCompare : null;
    final outcome = await service.join(
      ticket,
      identity: stored?.identity,
      confirmComparison: compare,
    );
    await _remember(
      outcome,
      address: '${ticket.host}:${ticket.port}',
      fallbackName: ticket.name,
    );
    state = SyncState(phase: SyncPhase.done, outcome: outcome, scope: _scope);
  }

  /// Syncs with a device this one already knows, **with no pairing code at all**.
  ///
  /// **This is what the long-term key was for.** The first meeting was authenticated by six
  /// characters a human arranged; the key learned during it authenticates every meeting after, so
  /// the ticket here carries an address and no token, and the handshake refuses anything at that
  /// address that cannot prove it holds the remembered key. An address is a weak thing to depend on
  /// -- somebody else on the network can take an IP -- which is exactly why the *key* is what is
  /// checked and the address is only where this device looks.
  Future<void> joinRemembered(TrustedDevice device) async {
    final address = device.address;
    if (address == null) return;
    final parts = address.split(':');
    if (parts.length != 2) return;
    final port = int.tryParse(parts[1]);
    if (port == null) return;

    final service = await _ensure();
    if (service == null) return;
    final stored = _storedIdentity();
    state = SyncState(phase: SyncPhase.working, scope: _scope);
    final outcome = await service.join(
      PairingTicket(host: parts[0], port: port, token: '', name: device.name),
      identity: stored?.identity,
      expectedIdentity: device.publicKey,
    );
    await _remember(outcome, address: address, fallbackName: device.name);
    state = SyncState(phase: SyncPhase.done, outcome: outcome, scope: _scope);
  }

  /// This device's identity **if it is already loaded**, and null if it is not.
  ///
  /// **Read, not awaited, and that is a decision about the button.** Awaiting the provider on the way
  /// into a sync made the button depend on a file read that goes through a platform channel -- and in
  /// a widget test that channel is absent, so the future never completed and pressing the button did
  /// nothing at all. The tests caught it, but the shape of the mistake is the one `_ensure` already
  /// documents for the cellar: **a control that silently does nothing is the worst failure mode a
  /// screen has.** The section watches this provider, so the load starts when the screen is drawn and
  /// a person has long finished reading it before they tap anything.
  ///
  /// Null is not fatal: a device with no identity yet syncs exactly as it did before this feature --
  /// encrypted, authenticated by the code, unable to be recognised next time. Worse, and working.
  StoredSyncIdentity? _storedIdentity() => ref.read(syncIdentityProvider).value;

  /// Writes down who the peer turned out to be, so the next sync needs no code.
  Future<void> _remember(
    ExchangeOutcome outcome, {
    required String? address,
    String fallbackName = '',
  }) async {
    if (!outcome.succeeded || outcome.peerIdentity.isEmpty) return;
    final name = outcome.peerName.isNotEmpty
        ? outcome.peerName
        : (fallbackName.isNotEmpty ? fallbackName : 'peer');
    try {
      await ref.read(syncIdentityProvider.notifier).remember(
        TrustedDevice(
          publicKey: outcome.peerIdentity,
          name: name,
          address: address,
          lastSeenMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } on Object {
      // A device that was not remembered is a device that will ask for a code again. Not worth
      // failing a sync that already succeeded over.
    }
  }

  /// Stops whatever is in flight and goes back to the beginning.
  Future<void> cancel() async {
    await _service?.stop();
    state = const SyncState();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);

/// Section 12.3's "devices and sync", which until now was three shut doors and no way to open one.
///
/// **The code is text, and that is a decision rather than a missing feature.** A camera would be the
/// pleasant way to move a pairing code between two screens, and it is platform code that cannot be
/// built or tested in this environment. What [PairingTicket] already anticipated is the case a
/// camera cannot serve anyway -- the guest network with client isolation, the phone whose camera is
/// cracked -- and its own documentation says the string is short enough to be read aloud. So this
/// screen shows the string, selectable, and takes one typed in. When a camera arrives it becomes a
/// second way to fill the same field.
///
/// **Both directions are on one screen, and the labels say which is which.** A device is either
/// showing a code or typing one, never both, so the section shows the two actions rather than a
/// mode switch -- and the moment one is chosen, the other is replaced by what is happening.
class SyncSection extends ConsumerStatefulWidget {
  const SyncSection({super.key});

  @override
  ConsumerState<SyncSection> createState() => _SyncSectionState();
}

class _SyncSectionState extends ConsumerState<SyncSection> {
  final _code = TextEditingController();

  /// The token the reader chose for this session's share code, if they chose one.
  ///
  /// Empty means "let the generator pick", which is what the field says it will do -- and the label states the
  /// cost, because the token is the only thing standing between a first meeting and somebody else on the same
  /// network completing it (`domain/sync/pairing.dart`, `ShareCode`).
  final _shareToken = TextEditingController();

  /// **How long the screen has been open, for the reachable listener.**
  ///
  /// Not state and not a rebuild trigger: the listener is opened once per screen, guarded by the flag below so a
  /// rebuild of the section cannot bind a second socket on a second port -- an announcement can name only one.
  bool _listening = false;

  /// **The controller, kept in a field rather than read from `ref` when the screen goes away.**
  ///
  /// `ref` is tied to this widget's `BuildContext`, and `dispose` runs when that context is already unsafe -- so
  /// reading the provider there throws `Bad state: Using "ref" when a widget is about to or has been unmounted is
  /// unsafe`, which is exactly what the first version of this did. The notifier outlives the widget, so holding it
  /// costs nothing.
  SyncController? _controller;

  @override
  void initState() {
    super.initState();
    // After the first frame, because opening the listener touches the cellar future and the identity provider and
    // neither is ready inside `initState`. `openForRequests` is idempotent, so a second call is free.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openForRequests());
  }

  /// **The screen opening is this device becoming reachable** (§10.3.2).
  ///
  /// Discovery already promised "while this screen is open, your devices can find each other"; the other half of
  /// that promise is being *tap-able*, which needs a listener whose port the announcement can carry. It is opened
  /// here rather than by the discovery provider because the screen outlives the sub-views that provider is torn
  /// down with: a comparison taking over the screen must not take away the socket the connection arrived on.
  void _openForRequests() {
    if (_listening || !mounted) return;
    final stored = ref.read(syncIdentityProvider).value;
    if (stored == null) {
      // The identity is still being read, or this device has none yet: nothing to announce under, so nothing to
      // listen for. The section watches that provider, so this runs again as soon as it arrives.
      return;
    }
    _listening = true;
    final controller = ref.read(syncControllerProvider.notifier);
    _controller = controller;
    unawaited(
      controller.openForRequests(
        identity: stored.identity,
        acceptedIdentities: {for (final device in stored.trusted) device.publicKey},
      ),
    );
  }

  @override
  void dispose() {
    // Leaving the screen gives both halves up at once: nobody can see this device, and nobody can reach it.
    unawaited(_controller?.closeForRequests());
    _code.dispose();
    _shareToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncControllerProvider);
    final controller = ref.read(syncControllerProvider.notifier);
    // **The shelves come from the log and not from the sync state.** They were in the state at first,
    // filled in when a service was built -- which is when an action *starts*, so the chooser appeared
    // only after somebody had already tried to sync. A fact about the cellar belongs to the cellar.
    final shelves = (ref.watch(cellarProvider).value?.shelf.shelves.toList() ?? <String>[])
      ..sort();
    // **Retried on every rebuild, and free after the first.** The identity is read from a file through a
    // platform channel, so it may arrive after the first frame -- and the listener cannot open without it. The
    // guard inside makes the retry idempotent, so no rebuild can bind a second socket on a second port.
    _openForRequests();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.cellarSync, style: HollowType.heading),
        const SizedBox(height: 8),
        DualCopyText(Copy.syncHint, style: HollowType.caption),
        const SizedBox(height: 14),
        switch (sync.phase) {
          SyncPhase.hosting => _HostingView(
            ticket: sync.ticket!,
            onStop: controller.cancel,
          ),
          // **The guarded case first**, because a `switch` reads in order: a plain `working` above it would
          // swallow every comparison and the screen would spin while a person waited to be asked something.
          SyncPhase.working when sync.comparingCode != null => _CompareView(
            code: sync.comparingCode,
            onAnswer: controller.answerComparison,
          ),
          SyncPhase.working => const _WorkingView(),
          _ => _ChooseView(
            code: _code,
            shareToken: _shareToken,
            outcome: sync.outcome,
            codeRejected: sync.codeRejected,
            onHost: () => controller.startHosting(token: _shareToken.text),
            onJoin: () => controller.join(_code.text),
            known: ref.watch(syncIdentityProvider).value?.trusted ?? const [],
            onSyncKnown: controller.joinRemembered,
            onForget: (device) =>
                ref.read(syncIdentityProvider.notifier).forget(device.publicKey),
            thisDevice: ref.watch(syncIdentityProvider).value?.identity,
            scope: sync.scope,
            shelves: shelves,
            onScope: controller.setScope,
            comparing: controller.comparisonWanted,
            onChooseMode: controller.chooseComparison,
            onConnectNearby: controller.joinNearby,
          ),
        },
      ],
    );
  }
}

/// The two ways to start, and the result of the last attempt.
/// **The six digits, and the two buttons that are the only way out of this screen.**
///
/// Nothing is exchanged while this is on screen: the exchange is stopped inside `runExchange`, waiting on the
/// future these buttons complete. So the screen is not a report of a decision already made -- it *is* the
/// decision, which is what makes a comparison worth anything.
///
/// **不一致 is not a retry.** Pressing it gives the session up and the reader is told why; there is no button
/// that asks the devices to try again, because twenty bits is enough exactly once and a retry loop would turn
/// "somebody has to guess one in a million" into "somebody has to guess one in a million as many times as they
/// like" (`ShortCode.isOneShot`). The way back is a new session, which is a new handshake and different digits.
class _CompareView extends StatelessWidget {
  const _CompareView({required this.code, required this.onAnswer});

  /// The digits derived from the handshake, or null if the session moved on before this was drawn.
  final String? code;

  final void Function({required bool agree}) onAnswer;

  @override
  Widget build(BuildContext context) {
    if (code == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        DualCopyText(Copy.compareTitle, style: HollowType.title),
        const SizedBox(height: 8),
        DualCopyText(Copy.compareNote, style: HollowType.caption),
        const SizedBox(height: 18),
        // Grouped in threes, because six digits in a row is a number to read and two groups of three is a
        // number to compare (`ShortCode.grouped`).
        SelectableText(
          ShortCode.grouped(code!),
          key: const ValueKey('compare-code'),
          style: HollowType.display.copyWith(letterSpacing: 6),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton(
              key: const ValueKey('compare-agree'),
              onPressed: () => onAnswer(agree: true),
              child: DualCopyText(Copy.compareAgree, style: HollowType.body),
            ),
            const SizedBox(width: 16),
            TextButton(
              key: const ValueKey('compare-refuse'),
              onPressed: () => onAnswer(agree: false),
              child: DualCopyText(Copy.compareRefuse, style: HollowType.body),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DualCopyText(Copy.compareRefuseNote, style: HollowType.caption),
      ],
    );
  }
}

class _ChooseView extends ConsumerWidget {
  const _ChooseView({
    required this.code,
    required this.shareToken,
    required this.outcome,
    required this.codeRejected,
    required this.onHost,
    required this.onJoin,
    required this.known,
    required this.onSyncKnown,
    required this.onForget,
    required this.thisDevice,
    required this.scope,
    required this.shelves,
    required this.onScope,
    required this.comparing,
    required this.onChooseMode,
    required this.onConnectNearby,
  });

  final TextEditingController code;

  /// Where a reader types the token they want inside the code they are about to show.
  final TextEditingController shareToken;
  final ExchangeOutcome? outcome;
  final bool codeRejected;
  final VoidCallback onHost;
  final VoidCallback onJoin;

  /// The devices this one has learned, and the two things a reader can do about each.
  final List<TrustedDevice> known;
  final void Function(TrustedDevice) onSyncKnown;
  final void Function(TrustedDevice) onForget;

  /// **The tap on a nearby device, after the reader confirmed the box** (§10.3.2 ①).
  final void Function(DiscoveredDevice) onConnectNearby;

  /// **Which way of adding a device is chosen**: false is the pairing code, true is comparing two screens.
  ///
  /// A choice rather than a setting: it decides the first step of *this* session, and a reader who compared two
  /// screens once has not asked to compare them every time.
  final bool comparing;
  final void Function({required bool compare}) onChooseMode;

  /// This device's own identity, so its fingerprint can be read out and compared.
  final DeviceIdentity? thisDevice;

  /// What the share will carry, and the shelves it could be limited to.
  ///
  /// **The chooser is only drawn when there is more than one shelf**, and that is not an oversight:
  /// section 12.3's Bar tab already refuses to build a shelf chooser over a single shelf, calling it
  /// furniture, and the same argument holds here -- a control whose two options do the same thing
  /// teaches a reader that the control does nothing. The mechanism underneath is finished and tested;
  /// it appears the day a second Bar exists.
  final SyncScope scope;
  final List<String> shelves;
  final void Function(SyncScope) onScope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.syncTokenLabel, style: HollowType.caption),
        const SizedBox(height: 6),
        // **The reader's own token, and the rule is stated rather than enforced silently.** Six to eight
        // characters from the alphabet that has no `I`, `O`, `0` or `1`; what the code carries is an address, so
        // the token is the only secret in it and a weak one is a first meeting somebody else can complete.
        TextField(
          key: const ValueKey('sync-token'),
          controller: shareToken,
          style: HollowType.body,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            // Upper case, and only the characters the alphabet holds: a field that accepts what it will refuse
            // later teaches the reader to distrust the message that comes next.
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z${ShareCode.alphabet}]')),
            LengthLimitingTextInputFormatter(ShareCode.maxTokenLength),
          ],
          decoration: const InputDecoration(
            hintText: 'RNDK7M',
            isDense: true,
          ),
        ),
        const SizedBox(height: 4),
        DualCopyText(Copy.syncTokenNote, style: HollowType.caption),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: onHost,
          child: DualCopyText(Copy.syncShowCode, style: HollowType.body),
        ),
        const SizedBox(height: 18),
        DualCopyText(Copy.syncEnterLabel, style: HollowType.caption),
        const SizedBox(height: 4),
        // The code is text, which means the address inside it is text too: a reader on a network where
        // the host guessed wrong can correct the address and keep the token.
        DualCopyText(Copy.syncEditHostHint, style: HollowType.caption),
        const SizedBox(height: 6),
        TextField(
          // **Keyed, because there are two fields in this section now.** A test that said
          // `find.byType(TextField)` was unambiguous while the code was the only one, and adding the token
          // field turned it into "too many elements" -- a failure that names neither field. The keys say which
          // one is meant.
          key: const ValueKey('sync-code'),
          controller: code,
          style: HollowType.body,
          decoration: const InputDecoration(
            hintText: 'hollowcourt://… · A7K3M9XQ2P-RNDK7M',
            isDense: true,
          ),
          onSubmitted: (_) => onJoin(),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: onJoin,
          child: DualCopyText(Copy.syncJoin, style: HollowType.body),
        ),
        if (codeRejected) ...[
          const SizedBox(height: 12),
          // Not `const`: the colour comes from the palette in force, which is a getter now, so a
          // const widget would freeze whichever theme this file was compiled against.
          DualCopyText(
            Copy.syncBadCode,
            // The colour goes through the style: `DualCopyText` derives the secondary from it, so
            // passing a colour separately would tint only the reader's language and leave the
            // reference language in the ordinary one.
            style: TextStyle(color: HollowPalette.rose, fontSize: 12, height: 1.45),
          ),
        ],
        if (outcome != null) ...[
          const SizedBox(height: 16),
          _OutcomeView(outcome: outcome!),
        ],
        if (shelves.length > 1) ...[
          const SizedBox(height: 22),
          DualCopyText(Copy.syncScope, style: HollowType.title),
          const SizedBox(height: 6),
          DualCopyText(Copy.syncScopeNote, style: HollowType.caption),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('scope-everything'),
                label: Text(
                  ref.copy(Copy.syncScopeAll),
                  style: HollowType.caption,
                ),
                selected: scope.isEverything,
                onSelected: (_) => onScope(const SyncScope.everything()),
              ),
              for (final shelf in shelves)
                ChoiceChip(
                  key: ValueKey('scope-$shelf'),
                  label: Text(shelf, style: HollowType.caption),
                  selected: scope.shelfId == shelf,
                  onSelected: (_) => onScope(SyncScope.shelf(shelf)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 28),
        // **The carrier that works when nothing else does**, below the ones that need a network -- and it needs
        // no explanation of why it is there, because its note says it.
        const PackCarrier(),
        // **How to add a device: two ways, and the reader picks** (the owner, 2026-09-22). A chip row rather
        // than two separate buttons, because both end in the same place -- a session -- and only the first step
        // differs: one types a code, the other looks at two screens.
        Row(
          children: [
            ChoiceChip(
              key: const ValueKey('mode-code'),
              label: DualCopyText(Copy.compareModeCode, style: HollowType.caption),
              selected: !comparing,
              onSelected: (_) => onChooseMode(compare: false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              key: const ValueKey('mode-compare'),
              label: DualCopyText(Copy.compareModeCompare, style: HollowType.caption),
              selected: comparing,
              onSelected: (_) => onChooseMode(compare: true),
            ),
          ],
        ),
        const SizedBox(height: 6),
        DualCopyText(
          comparing ? Copy.compareModeCompareNote : Copy.compareModeCodeNote,
          style: HollowType.caption,
        ),
        const SizedBox(height: 12),
        // **The cable, when there is one**, above the wireless list because it is the path that needs no
        // network at all.
        const UsbCableRow(),
        // **The link first, then who is on it.** What kind of network this is decides whether discovery can
        // work at all -- a tunnel or a client-isolated wireless is exactly where the code is the path.
        const LinkRow(),
        // **And then the two things a host owes the other end** (§10.3.2 ②): the port it is listening on, and its
        // own verdict about whether anything can reach it. Above the list, because the machine that has the
        // problem is the one that should be saying so.
        const ReachableRow(),
        const HostFirewallRow(),
        // **Discovery first, the store second.** What is on the network right now is the more useful list --
        // and a remembered device that is present appears in both, which is how the reader can tell "I know
        // this phone" from "this phone is here".
        NearbyDevices(
          known: known,
          // **The tap, once the reader has confirmed it** (§10.3.2): a remembered device is reached with the key
          // it learned, a stranger by comparing six digits on two screens. Which of the two it is was already
          // said in the box, so this method only has to do it.
          onConnect: onConnectNearby,
        ),
        _KnownDevices(
          known: known,
          thisDevice: thisDevice,
          onSync: onSyncKnown,
          onForget: onForget,
        ),
      ],
    );
  }
}

/// The devices this one has learned, and what their keys are worth.
///
/// **The list is the feature.** Section 10.3 asks for long-term keys exchanged during pairing, and a
/// key nobody can see, withdraw from, or compare is a key that exists in a file and nowhere a person
/// can act on it. So this shows what was learned, lets a sync be started from it with no code, and
/// lets a decision be undone -- which is the difference between a trust decision and a trap.
///
/// **The fingerprints are for reading aloud.** Two people looking at two screens can compare
/// `ABCD-EFGH-...` and notice a substitution; that is the only job the value has, and it is why it is
/// called a fingerprint rather than a key.
/// **The devices this one can hear right now.**
///
/// Drawn above the code entry on purpose: section 10.2.1 makes discovery the pleasant path and the pairing code
/// the one that always works, and a screen that put twelve characters of typing first would be a screen that
/// taught the reader the wrong one. The list appears only when there is something in it -- an empty "nearby
/// devices" heading on a network with client isolation would be a promise nobody can keep.
///
/// **Every row says what it is worth.** A remembered device is labelled and one tap reconnects it; a stranger
/// is labelled as new and still needs the code. The fingerprint is shown in short form because two devices can
/// share a name and the finger is the only thing on the line that a person can check.
/// **The USB cable, offered when a cable is actually worth offering.**
///
/// The carrier is `data/sync/adb_carrier.dart`: `adb forward` points a loopback port on this machine at the
/// sync port on the phone, so the handshake, the key and the scope are the same code the wireless path uses.
/// What this widget adds is the honest part -- **whether the tool is present at all**. `adb` ships with the
/// Android platform tools, a developer has it and a reader does not, so the row says which of the three
/// situations applies (ready, no tool, no usable device) rather than failing at the end of a handshake with a
/// sentence about sockets.
///
/// **The forward is set up and then left alone.** Nothing here connects or syncs; it produces an address --
/// `127.0.0.1:<port>` -- which is what the reader needs, because the datagrams then never leave the cable and
/// no network on either side is involved.
class UsbCableRow extends ConsumerStatefulWidget {
  const UsbCableRow({super.key});

  @override
  ConsumerState<UsbCableRow> createState() => _UsbCableRowState();
}

class _UsbCableRowState extends ConsumerState<UsbCableRow> {
  AdbStatus? _status;
  AdbForward? _forwarded;
  String? _refusal;
  bool _busy = false;

  // **Nothing runs until somebody asks.** The first version of this widget inspected `adb` in `initState`,
  // which meant a subprocess on every open of the sync screen -- impolite on a desktop, and in a widget test
  // it left a pending timer that failed eight unrelated tests on the 记录 tab. The cable is offered when the
  // reader asks about it, which is also the only moment the answer is worth having.
  Future<void> _inspect() async {
    setState(() => _busy = true);
    try {
      final status = await const AdbCarrier().inspect();
      if (mounted) setState(() => _status = status);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forward() async {
    setState(() {
      _busy = true;
      _refusal = null;
    });
    try {
      final (forward, refusal) = await const AdbCarrier().forward(
        devicePort: defaultAdbDevicePort,
      );
      if (!mounted) return;
      setState(() {
        _forwarded = forward;
        _refusal = refusal?.sentence;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    // **Before anybody asks, the row is an offer rather than a verdict.** It appears only once the reader has
    // asked whether the cable can be used, and it disappears again if the tool turns out not to be installed --
    // a permanent "USB direct connection: unavailable" on every machine without the Android platform tools
    // would be noise on a screen about syncing a cellar, and a reader would learn a feature exists only to be
    // told they cannot have it.
    if (status == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(Icons.usb, size: 18, color: HollowPalette.gold),
            const SizedBox(width: 8),
            Expanded(child: DualCopyText(Copy.usbTitle, style: HollowType.body)),
            TextButton(
              key: const ValueKey('usb-check'),
              onPressed: _busy ? null : _inspect,
              child: DualCopyText(Copy.usbCheck, style: HollowType.body),
            ),
          ],
        ),
      );
    }
    if (status.availability == AdbAvailability.noTool) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '${ref.copy(Copy.usbTitle)} — ${status.sentence}',
          key: const ValueKey('usb-no-tool'),
          style: HollowType.caption,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.usb, size: 18, color: HollowPalette.gold),
              const SizedBox(width: 8),
              Expanded(child: DualCopyText(Copy.usbTitle, style: HollowType.body)),
              if (status.availability == AdbAvailability.ready)
                TextButton(
                  key: const ValueKey('usb-forward'),
                  onPressed: _busy ? null : _forward,
                  child: DualCopyText(Copy.usbForward, style: HollowType.body),
                ),
            ],
          ),
          const SizedBox(height: 4),
          // The tool's own verdict, in words that say where to fix it: "not authorised" sends the reader to the
          // phone's screen, "nothing is plugged in" sends them to the cable.
          Text(status.sentence, style: HollowType.caption),
          if (_forwarded != null) ...[
            const SizedBox(height: 6),
            DualCopyText(Copy.usbReady, style: HollowType.caption),
            const SizedBox(height: 2),
            SelectableText(_forwarded!.hostAndPort, style: HollowType.numeric),
          ],
          if (_refusal != null) ...[
            const SizedBox(height: 6),
            Text(
              _refusal!,
              key: const ValueKey('usb-refusal'),
              style: HollowType.caption.copyWith(color: HollowPalette.rose),
            ),
          ],
        ],
      ),
    );
  }
}

/// **What kind of link this device is reachable on, said on the screen.**
///
/// The four modes exist in `domain/sync/link_mode.dart` with eleven tests, and until now nothing in the
/// interface mentioned any of them: the reader could not tell whether they were about to sync over Wi-Fi, a
/// cable, a USB tether or a VPN tunnel -- and those four behave differently in exactly the situations this
/// section is about (10.2.0.3 to 10.2.0.5). A tunnel is the one worth naming: it is the mode that works across
/// two networks that cannot see each other, and it is the mode a reader is least likely to know they are on.
///
/// **An unclassifiable interface says so rather than guessing.** `classifyLink` returns null for names it does
/// not recognise (a virtual adapter, a driver's own name), and the honest line is that nobody knows what this
/// link is -- the sync is still attempted, and if it fails the reason is on the screen rather than in a log.
class LinkRow extends ConsumerWidget {
  const LinkRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidate = ref.watch(lanCandidateProvider).value;
    if (candidate == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DualCopyText(Copy.syncLinkNone, style: HollowType.caption),
      );
    }
    final link = classifyLink(candidate.interfaceName);
    final label = switch (link) {
      SyncLink.wired => Copy.syncLinkWired,
      SyncLink.wireless => Copy.syncLinkWireless,
      SyncLink.usb => Copy.syncLinkUsb,
      SyncLink.tunnel => Copy.syncLinkTunnel,
      null => Copy.syncLinkUnknown,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            switch (link) {
              SyncLink.wired => Icons.cable,
              SyncLink.wireless => Icons.wifi,
              SyncLink.usb => Icons.usb,
              SyncLink.tunnel => Icons.vpn_lock,
              null => Icons.help_outline,
            },
            size: 18,
            color: HollowPalette.gold,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${label.primary.text}  ·  ${candidate.address}  (${candidate.interfaceName})',
              style: HollowType.caption,
            ),
          ),
        ],
      ),
    );
  }
}

/// The interface this device would be reached on, for [LinkRow].
///
/// A `FutureProvider` because enumerating interfaces is a platform call, and one that can fail; the row shows
/// the honest "no address" line rather than an error box, because a machine with no LAN address is a machine
/// that needs the pairing code and nothing else.
/// **How [HostFirewallRow] asks the operating system about itself.**
///
/// A provider rather than a class named inside the widget, and for the reason `SyncServiceFactory` is one: the
/// row's interesting behaviour -- which sentence a verdict produces, when the command appears, what the copy
/// button copies -- is decidable from a `FirewallFacts` a test writes, and a widget test that shelled out to
/// `powershell.exe` would be slow, machine-dependent, and unable to produce the refusal on demand.
final firewallProbeProvider = Provider<FirewallProbe>((ref) => const HostFirewallProbe());

final lanCandidateProvider = FutureProvider<LanCandidate?>((ref) => lanCandidate());

/// **The other half of being discoverable** (§10.3.2): this device is not only announcing itself, it is
/// listening, and the port is the one the announcement carries.
///
/// The row exists because the two halves can come apart without either one looking wrong: the list still fills
/// with neighbours, the code still appears, and every request to *this* machine goes into a closed port. Saying
/// the port out loud is cheap, and it is the fact a reader needs when the other end is the one timing out.
class ReachableRow extends ConsumerWidget {
  const ReachableRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final port = ref.watch(reachablePortProvider);
    if (port == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.meeting_room_outlined, size: 18, color: HollowPalette.gold),
          const SizedBox(width: 8),
          Expanded(child: DualCopyText(Copy.syncReachable, style: HollowType.caption)),
          const SizedBox(width: 8),
          // Selectable, so the port can be read off a photograph or copied into a rule.
          SelectableText(
            ':$port',
            key: const ValueKey('reachable-port'),
            style: HollowType.numeric,
          ),
        ],
      ),
    );
  }
}

/// **The host asking about its own inbound door, and saying the answer out loud** (§10.3.2 ②, the owner's
/// request of 2026-09-23).
///
/// The scene this is for: a phone said `could not reach 192.168.31.157:10838 -- Connection timed out`, and the
/// machine with the problem said nothing at all. So the machine that has the problem is the one that speaks --
/// it knows which address its listener is on, which category Windows has put this network in, and whether any
/// inbound rule names this program. One button, one sentence, and a command to copy when the sentence is a
/// refusal.
///
/// **It reads and never writes.** Nothing here changes the firewall; the command is offered to a person, who
/// decides. A program that quietly widened a rule on startup would be a worse neighbour than the timeout.
class HostFirewallRow extends ConsumerStatefulWidget {
  const HostFirewallRow({super.key});

  @override
  ConsumerState<HostFirewallRow> createState() => _HostFirewallRowState();
}

class _HostFirewallRowState extends ConsumerState<HostFirewallRow> {
  FirewallFacts? _facts;
  bool _checking = false;
  bool _copied = false;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _copied = false;
    });
    final facts = await ref.read(firewallProbeProvider).check(
      // The address the listener is on, which the row above is already drawing: the process that bound the
      // socket is the one that knows where it bound it.
      listenAddress: ref.read(lanCandidateProvider).value?.address ?? '',
    );
    if (!mounted) return;
    setState(() {
      _facts = facts;
      _checking = false;
    });
  }

  /// The one sentence, chosen from the verdict rather than written here.
  static CopyLine _sentence(FirewallVerdict verdict) => switch (verdict) {
    FirewallVerdict.open => Copy.firewallVerdictOpen,
    FirewallVerdict.loopbackOnly => Copy.firewallVerdictLoopback,
    FirewallVerdict.noAddress => Copy.firewallVerdictNoAddress,
    FirewallVerdict.noRule => Copy.firewallVerdictNoRule,
    FirewallVerdict.wrongProfile => Copy.firewallVerdictWrongProfile,
    FirewallVerdict.unknown => Copy.firewallVerdictUnknown,
  };

  @override
  Widget build(BuildContext context) {
    // **A Windows question, asked only on Windows.** The check runs `powershell.exe`; on the other two targets
    // the row would be a button that reports "cannot tell" forever, which is furniture (12.3's rule).
    if (!Platform.isWindows) return const SizedBox.shrink();

    final facts = _facts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DualCopyText(Copy.firewallTitle, style: HollowType.title),
          const SizedBox(height: 6),
          DualCopyText(Copy.firewallNote, style: HollowType.caption),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('firewall-check'),
            onPressed: _checking ? null : _check,
            child: DualCopyText(
              _checking ? Copy.firewallChecking : Copy.firewallCheck,
              style: HollowType.body,
            ),
          ),
          if (facts != null) ...[
            const SizedBox(height: 10),
            DualCopyText(
              _sentence(verdictOf(facts)),
              style: HollowType.body,
            ),
            const SizedBox(height: 8),
            _fact(Copy.firewallProgramLabel, facts.program),
            _fact(
              Copy.firewallProfileLabel,
              facts.categories.isEmpty ? ref.copy(Copy.firewallNone) : facts.categories.join(', '),
            ),
            _fact(
              Copy.firewallRuleLabel,
              facts.rules.isEmpty
                  ? ref.copy(Copy.firewallNone)
                  : facts.rules.map((rule) => rule.name).join(' · '),
            ),
            const SizedBox(height: 6),
            // **The command, when there is something to do.** A verdict of "covered" is its own answer and a
            // command under it would only invite a reader to add a rule they do not need.
            if (verdictOf(facts) != FirewallVerdict.open &&
                verdictOf(facts) != FirewallVerdict.unknown) ...[
              DualCopyText(Copy.firewallPortNote, style: HollowType.caption),
              const SizedBox(height: 6),
              SelectableText(
                allowCommandFor(facts.program),
                key: const ValueKey('firewall-command'),
                style: HollowType.numeric,
              ),
              const SizedBox(height: 6),
              TextButton(
                key: const ValueKey('firewall-copy'),
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: allowCommandFor(facts.program)),
                  );
                  if (!mounted) return;
                  setState(() => _copied = true);
                },
                child: DualCopyText(
                  _copied ? Copy.firewallCopied : Copy.firewallCopy,
                  style: HollowType.caption,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// One labelled fact, with the value selectable because a program path is something a reader copies.
  static Widget _fact(CopyLine label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(label, style: HollowType.caption),
        const SizedBox(height: 2),
        SelectableText(value, style: HollowType.numeric),
      ],
    ),
  );
}


class NearbyDevices extends ConsumerWidget {
  const NearbyDevices({
    super.key,
    required this.known,
    required this.onConnect,
  });

  final List<TrustedDevice> known;

  /// **Called once the reader has confirmed the box, and only then** (§10.3.2, the owner's decision).
  ///
  /// The wiring is a callback rather than a direct call into the controller so the box can be tested without
  /// one: what the screen owes a reader is "nothing happens until you say so", and that is assertable on its own.
  final void Function(DiscoveredDevice) onConnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nearby = ref.watch(discoveredDevicesProvider).value ?? const <DiscoveredDevice>[];
    if (nearby.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.syncNearbyTitle, style: HollowType.title),
        const SizedBox(height: 6),
        DualCopyText(Copy.syncNearbyNote, style: HollowType.caption),
        const SizedBox(height: 8),
        for (final device in nearby)
          ListTile(
            key: ValueKey('nearby-${device.identityKey}'),
            dense: true,
            leading: Icon(
              device.remembered ? Icons.verified_user_outlined : Icons.help_outline,
              color: device.remembered ? HollowPalette.gold : HollowPalette.rose,
            ),
            title: Text(device.name, style: HollowType.body),
            subtitle: Text(
              '${device.address}:${device.port}  ·  ${_short(device.fingerprint)}'
              '${device.remembered ? '' : '  ·  ${ref.copy(Copy.syncNearbyNew)}'}',
              style: HollowType.caption,
            ),
            // **A remembered device is one tap from syncing; a stranger is one tap from being asked**
            // (§10.3.2). The keyboard was the honest icon while a stranger's tap put the cursor in the code
            // field, and it stopped being honest the moment the tap began asking first.
            trailing: device.remembered
                ? const Icon(Icons.sync)
                : const Icon(Icons.touch_app_outlined),
            // **A tap is a request to connect, not a connection** (§10.3.2). The box below is what says so, and
            // it says it with the fields the announcement actually carries -- a name, an address, a fingerprint
            // and whether this machine has met the device -- because a mis-tap here costs somebody a dialog on
            // another screen.
            onTap: () => _tap(context, device),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Opens the box, and connects only if it comes back true.
  Future<void> _tap(BuildContext context, DiscoveredDevice device) async {
    final agreed = await showDialog<bool>(
      context: context,
      // **The nearest navigator, not the root one.** `showDialog` defaults to the root navigator, and the box is
      // part of *this* screen: on a tree with one navigator the two are the same thing, and on any other tree the
      // root navigator is above the scope that holds this screen's providers -- which is the difference between a
      // box that can read a line of copy and `Bad state: No ProviderScope found`.
      useRootNavigator: false,
      builder: (context) => ConnectBox(device: device, known: known),
    );
    if (agreed != true) return;
    onConnect(device);
  }

  /// The first six characters, which is what a person can hold in their head while looking at another screen.
  ///
  /// **[defect] Of the digest, not of whatever spelling arrived.** The announcement carries the grouped form, so
  /// the old version printed `977T-G` -- six characters that are five of fingerprint and a separator. The row's
  /// whole job is a value a person compares, and half a group is not a value.
  static String _short(String fingerprint) {
    final digest = DeviceIdentity.fingerprintKey(fingerprint);
    return digest.length <= 6 ? digest : digest.substring(0, 6);
  }
}

/// **The confirmation a tap goes through, and every field on it is one the announcement already carries.**
///
/// The owner's decision (2026-09-23) was that tapping a device in 附近的设备 must not connect immediately: the
/// list row carries a name and six characters, and the box carries the rest. **Nothing here is promised that the
/// protocol does not have** -- the name is the sender's own claim, the address and port are where the datagram
/// actually came from, the fingerprint is the one value a device cannot invent about itself, and the last row is
/// derived from comparing that fingerprint with the keys this machine has stored.
///
/// **The fingerprint is the reason the box exists.** Everything else on it is convenience; this is the value that
/// turns "the device called laptop" into "the device whose key I learned in September".
class ConnectBox extends ConsumerWidget {
  const ConnectBox({super.key, required this.device, required this.known});

  final DiscoveredDevice device;

  /// The devices this machine has met, so the box can say what pressing the button will do.
  final List<TrustedDevice> known;

  /// The stored key this device's fingerprint names, or null when this machine has never met it.
  TrustedDevice? get _remembered {
    if (device.fingerprint.isEmpty) return null;
    for (final candidate in known) {
      if (DeviceIdentity.sameFingerprint(
        DeviceIdentity.fingerprintOf(candidate.publicKey),
        device.fingerprint,
      )) {
        return candidate;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remembered = _remembered != null;
    return AlertDialog(
      title: DualCopyText(Copy.syncConnectTitle, style: HollowType.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DualCopyText(Copy.syncConnectNote, style: HollowType.caption),
            const SizedBox(height: 14),
            _row(context, Copy.syncConnectNameLabel, device.name),
            _row(
              context,
              Copy.syncConnectAddressLabel,
              '${device.address}:${device.port}',
            ),
            _row(
              context,
              Copy.syncConnectFingerprintLabel,
              device.fingerprint.isEmpty ? ref.copy(Copy.firewallNone) : grouped(device.fingerprint),
            ),
            _row(
              context,
              Copy.syncConnectRememberedLabel,
              null,
              line: remembered ? Copy.syncConnectRememberedYes : Copy.syncConnectRememberedNo,
            ),
            _row(
              context,
              Copy.syncConnectNextLabel,
              null,
              line: remembered ? Copy.syncConnectNextStraight : Copy.syncConnectNextCompare,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('nearby-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: DualCopyText(Copy.syncConnectCancel, style: HollowType.caption),
        ),
        FilledButton(
          key: const ValueKey('nearby-connect'),
          onPressed: () => Navigator.of(context).pop(true),
          child: DualCopyText(Copy.syncConnectConfirm, style: HollowType.caption),
        ),
      ],
    );
  }

  /// One labelled row: a value this build read off the wire, or a sentence from the interface.
  static Widget _row(
    BuildContext context,
    CopyLine label,
    String? value, {
    CopyLine? line,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(label, style: HollowType.caption),
        const SizedBox(height: 2),
        if (value != null)
          SelectableText(value, style: HollowType.numeric)
        else if (line != null)
          DualCopyText(line, style: HollowType.body),
      ],
    ),
  );

  /// A fingerprint in groups of four, because it is read by eye across a table.
  ///
  /// **[defect] It groups the digest, not an already-grouped string.** The announcement's fingerprint is
  /// `2B99-RU9F-5B5V-XGDX`, and grouping *that* produced `2B99 -RU9 F-5B 5V-X GDX` -- photographed on a real
  /// screen and readable only because a person does not know what it was supposed to look like. Normalising first
  /// makes the box show `2B99 RU9F 5B5V XGDX`, which is the same value in the shape the design asked for.
  static String grouped(String fingerprint) {
    final digest = DeviceIdentity.fingerprintKey(fingerprint);
    final buffer = StringBuffer();
    for (var at = 0; at < digest.length; at += 4) {
      if (at > 0) buffer.write(' ');
      buffer.write(digest.substring(at, at + 4 > digest.length ? digest.length : at + 4));
    }
    return buffer.toString();
  }
}

class _KnownDevices extends StatelessWidget {
  const _KnownDevices({
    required this.known,
    required this.thisDevice,
    required this.onSync,
    required this.onForget,
  });

  final List<TrustedDevice> known;
  final DeviceIdentity? thisDevice;
  final void Function(TrustedDevice) onSync;
  final void Function(TrustedDevice) onForget;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.syncKnownHeading, style: HollowType.title),
        const SizedBox(height: 6),
        DualCopyText(Copy.syncKnownNote, style: HollowType.caption),
        if (thisDevice != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DualCopyText(Copy.syncThisDevice, style: HollowType.caption),
              ),
              const SizedBox(width: 12),
              SelectableText(thisDevice!.fingerprint, style: HollowType.numeric),
            ],
          ),
        ],
        const SizedBox(height: 10),
        if (known.isEmpty)
          DualCopyText(Copy.syncKnownEmpty, style: HollowType.caption)
        else
          for (final device in known)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.name, style: HollowType.body),
                  const SizedBox(height: 2),
                  SelectableText(
                    device.address ?? device.shortKey,
                    style: HollowType.caption,
                  ),
                  Row(
                    children: [
                      TextButton(
                        key: ValueKey('sync-known-\${device.shortKey}'),
                        onPressed: () => onSync(device),
                        child: DualCopyText(
                          Copy.syncKnownSync,
                          style: HollowType.caption,
                        ),
                      ),
                      TextButton(
                        key: ValueKey('forget-\${device.shortKey}'),
                        onPressed: () => onForget(device),
                        child: DualCopyText(
                          Copy.syncKnownForget,
                          style: HollowType.caption,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// The hosting side: the code, and what the other person is meant to do with it.
class _HostingView extends StatelessWidget {
  const _HostingView({required this.ticket, required this.onStop});

  final PairingTicket ticket;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.syncCodeLabel, style: HollowType.caption),
        const SizedBox(height: 6),
        // **The short share code first, because that is what the other device's field now asks for.**
        // Sixteen to eighteen characters instead of a fifty-character URI: the address still travels inside it,
        // so a network where broadcast does not cross is still served, and the token inside it is the one the
        // reader chose above. The URI stays underneath in caption size for the two cases the short form cannot
        // serve -- a host whose address is not IPv4, where `shareCode()` is null, and the repair
        // `syncEditHostHint` describes, where the address has to be editable by hand.
        SelectableText(
          ticket.shareCode() ?? ticket.encode(),
          key: const ValueKey('host-share-code'),
          style: HollowType.body.copyWith(letterSpacing: 1.6),
        ),
        if (ticket.shareCode() != null) ...[
          const SizedBox(height: 6),
          SelectableText(
            ticket.encode(),
            style: HollowType.caption,
          ),
        ],
        // **The warning that saves the first attempt.** A host on a machine whose only advertised
        // address is a loopback one produces a code that looks correct and cannot be reached -- and
        // everything the other device then says is about the handshake, so the machine that has the
        // problem says nothing. This is it saying something, before anybody types a URI into a phone.
        if (!looksReachableFromAnotherDevice(ticket.host)) ...[
          const SizedBox(height: 10),
          DualCopyText(
            Copy.syncAddressProblem,
            style: HollowType.caption.copyWith(color: HollowPalette.rose),
          ),
        ],
        const SizedBox(height: 12),
        DualCopyText(Copy.syncWaiting, style: HollowType.caption),
        const SizedBox(height: 10),
        const LinearProgressIndicator(minHeight: 2),
        const SizedBox(height: 10),
        TextButton(
          onPressed: onStop,
          child: DualCopyText(Copy.syncStop, style: HollowType.caption),
        ),
      ],
    );
  }
}

/// While a connection is being made or an exchange is running.
class _WorkingView extends StatelessWidget {
  const _WorkingView();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LinearProgressIndicator(minHeight: 2),
      SizedBox(height: 10),
      DualCopyText(Copy.syncConnecting, style: HollowType.caption),
    ],
  );
}

/// What the exchange did, or why it did not.
class _OutcomeView extends StatelessWidget {
  const _OutcomeView({required this.outcome});

  final ExchangeOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final failed = !outcome.succeeded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(
          failed ? Copy.syncFailed : Copy.syncDone,
          style: failed
              ? HollowType.heading.copyWith(color: HollowPalette.rose)
              : HollowType.heading,
        ),
        const SizedBox(height: 6),
        if (failed)
          // The transport's own words. See the note on `Copy.syncBadCode` for why these are not
          // translated: they are diagnostic, they are not a closed set, and matching on their text
          // to substitute a translation would break the first time one was reworded.
          Text(outcome.failure!, style: HollowType.caption)
        else if (outcome.merged == 0 && outcome.sent == 0)
          DualCopyText(Copy.syncNothingToDo, style: HollowType.caption)
        else ...[
          DualCopyText(Copy.syncMoved, style: HollowType.caption),
          const SizedBox(height: 4),
          Text('${outcome.merged} / ${outcome.sent}', style: HollowType.body),
        ],
        if (!failed && outcome.peerName.isNotEmpty) ...[
          const SizedBox(height: 8),
          DualCopyText(Copy.syncWith, style: HollowType.caption),
          const SizedBox(height: 4),
          Text(outcome.peerName, style: HollowType.body),
        ],
      ],
    );
  }
}
