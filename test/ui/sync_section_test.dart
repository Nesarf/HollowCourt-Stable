import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/data/sync/sync_service.dart';
import 'package:hollow_court/domain/sync/device_identity.dart';
import 'package:hollow_court/domain/sync/exchange.dart';
import 'package:hollow_court/domain/sync/pairing.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/data/sync/identity_store.dart';
import 'package:hollow_court/ui/sync_identity.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/shelf.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/sync/scope.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:hollow_court/ui/sync_section.dart';
import 'package:hollow_court/ui/theme.dart';

/// A service that does what a test tells it to, and remembers what it was asked.
///
/// **The peer's arrival is a [Completer] the test holds.** A fake that returned an outcome
/// immediately could never show the state this screen spends most of its life in -- the code on
/// screen, waiting -- and reaching it by racing a real send would be a test that passes on a fast
/// machine and fails on a slow one. Holding the future open makes "while waiting" an ordinary
/// assertion.
final class _FakeSync implements SyncService {
  _FakeSync({required this.ticket});

  final PairingTicket ticket;

  final List<String> calls = [];
  final Completer<ExchangeOutcome> peer = Completer<ExchangeOutcome>();

  /// What a join should come back with.
  ExchangeOutcome joinOutcome = const ExchangeOutcome(merged: 1, sent: 2, peerName: 'laptop');

  PairingTicket? joinedWith;

  /// What the controller handed the service: the identity this device offered, and the key it
  /// required of the peer. Recorded so a test can assert that a remembered device is synced **by its
  /// key with no token**, which is the whole point of learning one.
  DeviceIdentity? hostedAs;
  DeviceIdentity? joinedAs;
  String joinedExpecting = '';

  @override
  String get localName => 'test-device';

  @override
  Future<PairingTicket> host({
    DeviceIdentity? identity,
    String expectedIdentity = '',
    Set<String> acceptedIdentities = const {},
    // The reader's own token, when they typed one: the interface gained this on 2026-09-23 so that the token
    // half of a share code can be chosen. A fake that does not carry it cannot stand in for the real one.
    String? token,
  }) async {
    calls.add('host');
    hostedAs = identity;
    return ticket;
  }

  @override
  Future<ExchangeOutcome> awaitPeer({
    DeviceIdentity? identity,
    String expectedIdentity = '',
    Future<bool> Function(String shortCode)? confirmComparison,
  }) {
    // **This fake never runs an exchange, so it cannot honour a gate** -- and the parameter is named here rather
    // than ignored silently, because a fake that accepts a security parameter and drops it is a test that will
    // keep passing after the feature stops working.
    assert(
      confirmComparison == null,
      'this fake cannot answer a comparison; use the loopback service in p3_acceptance_test.dart',
    );
    calls.add('awaitPeer');
    return peer.future;
  }

  @override
  Future<ExchangeOutcome> join(
    PairingTicket target, {
    DeviceIdentity? identity,
    String expectedIdentity = '',
    Future<bool> Function(String shortCode)? confirmComparison,
  }) async {
    assert(confirmComparison == null, 'this fake cannot answer a comparison');
    calls.add('join');
    joinedWith = target;
    joinedAs = identity;
    joinedExpecting = expectedIdentity;
    return joinOutcome;
  }

  @override
  Future<void> stop() async => calls.add('stop');

  // ---- The reachable listener (§10.3.2), recorded apart from `calls`. ----
  //
  // **A list of its own, and not for tidiness.** Every existing test in this file asserts on `calls` as an exact
  // list of *session* verbs, and the screen now opens a listener as soon as it is drawn -- so recording both in one
  // list would have made nine tests about hosting and joining fail for a reason none of them is about.

  final List<String> listenerCalls = [];

  /// The port the listener reports, which is the one the announcement is meant to carry.
  int openPort = 48125;

  /// What the listener was given: this device's key, and the keys of everybody it remembers.
  DeviceIdentity? listeningAs;
  Set<String> listeningAccepting = const {};

  /// **A tap from a neighbour**, held open for the same reason [peer] is: "waiting to be tapped" is the state this
  /// device spends its life in, and it cannot be asserted if the future resolves immediately.
  final Completer<ExchangeOutcome> request = Completer<ExchangeOutcome>();

  /// **And the silence after it.** A listener does not stop being a listener once it has answered; it waits for
  /// the next tap. A fake that returned the same completed future again would hand the screen the same outcome in
  /// a tight loop -- which is not a slow test but a hung one, and it hung this whole file the first time.
  final Completer<ExchangeOutcome> _quiet = Completer<ExchangeOutcome>();
  var _answered = false;

  @override
  Future<int> openForRequests({
    DeviceIdentity? identity,
    Set<String> acceptedIdentities = const {},
  }) async {
    listenerCalls.add('openForRequests');
    listeningAs = identity;
    listeningAccepting = acceptedIdentities;
    return openPort;
  }

  @override
  Future<ExchangeOutcome> awaitRequest({
    DeviceIdentity? identity,
    Future<bool> Function(String shortCode)? confirmComparison,
  }) {
    // The listener is reachable by anybody, so the gate is not optional here: it is the proof this connection
    // otherwise does not have. A fake that accepted a null gate would hide exactly the bug this records.
    assert(
      confirmComparison != null,
      'a listener that cannot ask a person to compare digits accepts anybody',
    );
    listenerCalls.add('awaitRequest');
    if (_answered) return _quiet.future;
    _answered = true;
    return request.future;
  }

  @override
  Future<void> closeForRequests() async => listenerCalls.add('closeForRequests');
}

/// An identity that is already loaded, so a test does not need the file that holds one.
final class _FixedIdentity extends SyncIdentityNotifier {
  _FixedIdentity(this.identity);

  final DeviceIdentity identity;

  @override
  Future<StoredSyncIdentity> build() async =>
      StoredSyncIdentity(identity: identity, trusted: const []);
}

/// A cellar on disk, seeded with [events].
///
/// The events matter for the shelf chooser: whether it appears at all depends on there being more than
/// one shelf, and that is a fact about the log rather than about the screen.
Future<Cellar> _cellar(WidgetTester tester, [List<Event> events = const []]) async {
  final cellar = await tester.runAsync(() async {
    final dir = Directory.systemTemp.createTempSync('hollow_sync_ui');
    var clock = 1000;
    final log = await EventLog.open(
      file: File('${dir.path}${Platform.pathSeparator}cellar.ndjson'),
      nodeId: 'test',
      nowMillis: () => clock++,
    );
    for (final event in events) {
      await log.record((_) => event);
    }
    return Cellar.of(log);
  });
  return cellar!;
}

class _Seeded extends CellarNotifier {
  _Seeded(this._initial);
  final Cellar _initial;

  @override
  Future<Cellar> build() async => _initial;
}

/// Pumps the section alone, in a scroll view.
///
/// The scroll view is not decoration: the Cellar page hosts this inside a `ListView`, and a section
/// that only fits on one screen's worth of height would pass here and overflow there. The same
/// mistake is recorded against `SettingsSection`.
/// Every source the section has built a service around, in order.
final capturedSources = <SyncSource>[];

Future<_FakeSync> _pump(
  WidgetTester tester, {
  required Cellar cellar,
  DeviceIdentity? identity,
}) async {
  capturedSources.clear();
  final fake = _FakeSync(
    ticket: const PairingTicket(
      host: '192.168.1.5',
      port: 47821,
      token: 'K7FQ2M',
      name: 'laptop',
    ),
  );

  await tester.pumpWidget(
    ProviderScope(
     
      overrides: [
        localeSettingsProvider.overrideWith(() => _FixedLocale(
          const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: true),
        )),
        cellarProvider.overrideWith(() => _Seeded(cellar)),
        // The source is captured, not discarded: the scope this device offers lives in the source an
        // exchange reads through, so it is the one thing a screen test can check about it.
        syncServiceFactoryProvider.overrideWithValue((source) {
          capturedSources.add(source);
          return fake;
        }),
        if (identity != null)
          syncIdentityProvider.overrideWith(() => _FixedIdentity(identity)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SyncSection()),
        ),
      ),
    ),
  );
  // `pumpAndSettle`, not `pump`: the cellar arrives from an async provider, and the service is
  // built from it. A single pump left the screen idle-looking but unwired, and every test that
  // tapped a button then asserted on the fake passed or failed for the wrong reason -- the
  // "nothing was dialled" assertion in particular passed while nothing was even connected.
  // Safe here because the idle state draws no indeterminate animation; the hosting state does, and
  // those tests pump by hand.
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('the section offers both directions before anything is started', () {
    testWidgets('it shows a way to host and a field to join', (tester) async {
      await _pump(tester, cellar: await _cellar(tester));

      // Both languages, which is section 2.7's default and not a setting a test should have to
      // switch on to see the screen work.
      expect(find.text('显示配对码'), findsOneWidget);
      expect(find.text('Show a pairing code'), findsOneWidget);
      expect(find.text('对方的配对码'), findsOneWidget);
      expect(find.text('连接并同步'), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-code')), findsOneWidget);
      expect(find.byKey(const ValueKey('sync-token')), findsOneWidget,
          reason: 'the token the reader chooses sits above the host button');
    });
  });

  group('hosting shows the code and then waits in it', () {
    testWidgets('the code is on screen while the peer has not arrived', (tester) async {
      final fake = await _pump(tester, cellar: await _cellar(tester));

      // **Dragged into view, not merely "ensured".** The token field the reader may fill in sits above this
      // button, and on a page that already has a shelf chooser that is enough to push it to the very edge --
      // where `ensureVisible` stops, the tap misses by a few pixels, and the failure reads as
      // "the source was the plain log" rather than "nothing was tapped". `dragUntilVisible` moves it clear of
      // the edge.
      // **Pressed through its callback, because the geometry of this section is not what is under test.**
      // The button now sits below a token field and above a note, and in this test's page -- which already
      // carries a two-shelf chooser -- both "ensure" and "drag until visible" still left it un-hittable at its
      // centre, so the tap silently did nothing and the failure read as "the source was the plain log". What
      // this test is about is whether the chosen shelf reaches the exchange; where the button happens to land
      // is not.
      final hostButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '显示配对码'),
      );
      hostButton.onPressed!();
      await tester.pump();
      // `pump` rather than `pumpAndSettle`: the waiting state draws an indeterminate progress
      // indicator, whose animation never settles, so settling would time out on a screen that is
      // working exactly as intended.
      //
      // **Three pumps, and the third is the identity.** The controller now loads this device's key
      // before it binds a listener -- one more await than there used to be -- so a test that pumps
      // twice reaches the screen before the service has been touched. It showed up as an empty
      // `calls` list rather than as a failure to draw, which is why the assertion is on the calls.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(fake.calls, ['host', 'awaitPeer']);
      expect(
        find.text('hollowcourt://192.168.1.5:47821/K7FQ2M?name=laptop'),
        findsOneWidget,
      );
      expect(find.text('正在等待对方输入这串码…'), findsOneWidget);
      // **Two selectable strings now, and they are the two forms of the same ticket.** The short share code is
      // what the other device's field asks for; the URI underneath is what serves a host whose address is not
      // IPv4, and it is the form a reader can repair by hand. Both have to be on screen and copyable, because
      // both are meant to be read off one device and typed into another.
      expect(find.byType(SelectableText), findsNWidgets(2));
      expect(find.byKey(const ValueKey('host-share-code')), findsOneWidget,
          reason: 'the short code is the one offered first');
    });

    testWidgets('the outcome replaces the code when the peer arrives', (tester) async {
      final fake = await _pump(tester, cellar: await _cellar(tester));

      // **Dragged into view, not merely "ensured".** The token field the reader may fill in sits above this
      // button, and on a page that already has a shelf chooser that is enough to push it to the very edge --
      // where `ensureVisible` stops, the tap misses by a few pixels, and the failure reads as
      // "the source was the plain log" rather than "nothing was tapped". `dragUntilVisible` moves it clear of
      // the edge.
      await tester.dragUntilVisible(
        find.text('显示配对码'),
        find.byType(Scrollable).first,
        const Offset(0, -120),
      );
      await tester.pump();
      await tester.tap(find.text('显示配对码'));
      await tester.pump();
      await tester.pump();

      fake.peer.complete(
        const ExchangeOutcome(merged: 3, sent: 1, peerName: 'phone', peerReason: 'done'),
      );
      await tester.pump();
      await tester.pump();
      // One more, for the same reason as above: remembering the peer is an await on the way back.
      await tester.pump();

      expect(find.text('同步完成'), findsOneWidget);
      expect(find.text('3 / 1'), findsOneWidget);
      expect(find.text('phone'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      // And the two ways to start again are back, because a person may well sync twice.
      expect(find.text('显示配对码'), findsOneWidget);
    });

    testWidgets('stopping waiting closes the service and returns to the start', (tester) async {
      final fake = await _pump(tester, cellar: await _cellar(tester));

      // **Dragged into view, not merely "ensured".** The token field the reader may fill in sits above this
      // button, and on a page that already has a shelf chooser that is enough to push it to the very edge --
      // where `ensureVisible` stops, the tap misses by a few pixels, and the failure reads as
      // "the source was the plain log" rather than "nothing was tapped". `dragUntilVisible` moves it clear of
      // the edge.
      await tester.dragUntilVisible(
        find.text('显示配对码'),
        find.byType(Scrollable).first,
        const Offset(0, -120),
      );
      await tester.pump();
      await tester.tap(find.text('显示配对码'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('停止等待'));
      await tester.pump();

      expect(fake.calls, contains('stop'));
      expect(find.text('显示配对码'), findsOneWidget);
    });
  });

  group('being tapped, rather than tapping (§10.3.2)', () {
    testWidgets('**the screen opens a listener, and a tap that was answered is remembered**',
        (tester) async {
      final identity = await DeviceIdentity.generate();
      final fake = await _pump(
        tester,
        cellar: await _cellar(tester),
        identity: identity,
      );

      // **Reachable rather than showing a code.** The screen opens the listener as soon as it is drawn and has a
      // key to announce under, and it hands it this device's identity plus everybody it remembers -- which is the
      // whole difference between being tapped and hosting a code.
      expect(fake.listenerCalls, contains('openForRequests'));
      expect(fake.listeningAs, isNotNull);
      expect(fake.listenerCalls, contains('awaitRequest'));

      // A neighbour's tap arrives, and this device answers it. **Nothing merges**, because the two cellars are
      // already in sync -- which is the case the owner hit: a connection that succeeded, a reader who pressed
      // 一致, and a device that was not remembered.
      fake.request.complete(
        const ExchangeOutcome(
          merged: 0,
          sent: 0,
          peerName: 'laptop',
          peerIdentity: 'THE-LAPTOP-KEY',
          peerAddress: '192.168.31.157:13992',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('已记住的设备'), findsOneWidget);
      expect(find.text('laptop'), findsWidgets);
      // **And the address, which is what 再同步一次 dials.** A remembered key with nowhere to use it was the other
      // half of the same report.
      expect(find.text('192.168.31.157:13992'), findsWidgets);
    });

    testWidgets('**a close that arrives after a new screen has opened cannot take the socket away**',
        (tester) async {
      // The reported defect, reproduced at the level it lives at: the sync section is scrolled out of the list's
      // cache extent (which disposes it and closes the listener) and back (which opens one), and the two
      // asynchronous operations interleave -- so the *old* close landed on the *new* socket. On a phone the only
      // symptom was that 「附近的设备现在可以点到这台机器」 never came back, for the rest of the session.
      final fake = await _pump(
        tester,
        cellar: await _cellar(tester),
        identity: await DeviceIdentity.generate(),
      );
      final controller = ProviderScope.containerOf(
        tester.element(find.byType(SyncSection)),
      ).read(syncControllerProvider.notifier);

      // Close and open without awaiting either, which is exactly what dispose-then-mount does.
      final closing = controller.closeForRequests();
      final opening = controller.openForRequests(
        identity: null,
        acceptedIdentities: const {},
      );
      await closing;
      await opening;
      await tester.pump();

      // **The last of the two operations is the one that holds the socket.** `awaitRequest` is left out because it
      // is the accept loop starting *after* an open, not a change of ownership.
      final ownership = fake.listenerCalls.where((call) => call != 'awaitRequest').toList();
      expect(ownership, contains('closeForRequests'), reason: 'the old screen did close the listener');
      expect(ownership.last, 'openForRequests', reason: 'and the new screen had the last word');
      expect(
        find.byKey(const ValueKey('reachable-port')),
        findsOneWidget,
        reason: 'the device is reachable again, and says so',
      );
    });

    testWidgets('a tap that was answered says what happened, on this screen too', (tester) async {
      final fake = await _pump(
        tester,
        cellar: await _cellar(tester),
        identity: await DeviceIdentity.generate(),
      );

      fake.request.complete(
        const ExchangeOutcome(
          merged: 3,
          sent: 1,
          peerName: 'laptop',
          peerIdentity: 'THE-LAPTOP-KEY',
        ),
      );
      await tester.pump();
      await tester.pump();

      // The result of a request this device *answered* is reported in the same place a request it made is: one
      // screen, one outcome view, whichever direction the connection came from.
      expect(find.text('同步完成'), findsOneWidget);
      expect(find.text('3 / 1'), findsOneWidget);
    });
  });

  group('joining', () {
    testWidgets('a code that is not ours is refused before any connection', (tester) async {
      // The failure the reader caused, and the only one this screen words itself. The assertion
      // that matters is the second one: nothing was dialled, so a typo costs a message and not a
      // timeout against a host that was never going to answer.
      final fake = await _pump(tester, cellar: await _cellar(tester));

      await tester.enterText(find.byKey(const ValueKey('sync-code')), 'not a pairing code');
      await tester.tap(find.text('连接并同步'));
      await tester.pump();
      await tester.pump();

      expect(find.text('这不像是一个空庭的配对码。请检查有没有漏字。'), findsOneWidget);
      expect(fake.calls, isEmpty);

      // ...and then prove the quiet was the refusal and not a dead screen. Without this the
      // assertion above also passes when the service was never wired at all, which is exactly what
      // happened the first time this test ran.
      await tester.enterText(find.byKey(const ValueKey('sync-code')), 'hollowcourt://10.0.0.9:51000/AB23CD');
      await tester.tap(find.text('连接并同步'));
      await tester.pump();
      await tester.pump();
      expect(fake.calls, ['join']);
    });

    testWidgets('a good code is dialled and the answer is shown', (tester) async {
      final fake = await _pump(tester, cellar: await _cellar(tester));

      await tester.enterText(
        find.byKey(const ValueKey('sync-code')),
        'hollowcourt://10.0.0.9:51000/AB23CD',
      );
      await tester.tap(find.text('连接并同步'));
      await tester.pump();
      await tester.pump();

      expect(fake.calls, ['join']);
      expect(fake.joinedWith!.host, '10.0.0.9');
      expect(fake.joinedWith!.port, 51000);
      expect(fake.joinedWith!.token, 'AB23CD');
      expect(find.text('同步完成'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('two cellars that already match are told so rather than shown a zero', (tester) async {
      final fake = await _pump(tester, cellar: await _cellar(tester));
      fake.joinOutcome = const ExchangeOutcome(merged: 0, sent: 0, peerName: 'laptop');

      await tester.enterText(find.byKey(const ValueKey('sync-code')), 'hollowcourt://10.0.0.9:51000/AB23CD');
      await tester.tap(find.text('连接并同步'));
      await tester.pump();
      await tester.pump();

      expect(find.text('两边已经一样了，没有需要传的。'), findsOneWidget);
      expect(find.text('0 / 0'), findsNothing);
    });

    testWidgets('a failed exchange shows the transport reason as it arrived', (tester) async {
      // Deliberately not translated -- see the note on `Copy.syncBadCode`. What is asserted is that
      // the reason reaches the reader at all, because a failure that is swallowed is worse than one
      // in the wrong language.
      final fake = await _pump(tester, cellar: await _cellar(tester));
      fake.joinOutcome = const ExchangeOutcome(
        merged: 0,
        sent: 0,
        failure: 'could not reach 10.0.0.9:51000 -- Connection refused',
      );

      await tester.enterText(find.byKey(const ValueKey('sync-code')), 'hollowcourt://10.0.0.9:51000/AB23CD');
      await tester.tap(find.text('连接并同步'));
      await tester.pump();
      await tester.pump();

      expect(find.text('没能同步'), findsOneWidget);
      expect(find.textContaining('Connection refused'), findsOneWidget);
    });
  });

  group('a device that was met once is remembered, and needs no code again', () {
    testWidgets('a successful pairing writes the device down', (tester) async {
      final identity = await DeviceIdentity.generate();
      final fake = await _pump(
        tester,
        cellar: await _cellar(tester),
        identity: identity,
      );
      fake.joinOutcome = const ExchangeOutcome(
        merged: 2,
        sent: 0,
        peerName: 'laptop',
        peerIdentity: 'THE-LAPTOP-KEY',
      );

      await tester.enterText(find.byKey(const ValueKey('sync-code')), fake.ticket.encode());
      await tester.tap(find.text('连接并同步'));
      await tester.pump();
      await tester.pump();

      // The device is on the screen, under the heading that says what remembering means.
      expect(find.text('已记住的设备'), findsOneWidget);
      expect(find.text('laptop'), findsWidgets);
      expect(find.text('192.168.1.5:47821'), findsWidgets);
      // And this device's own fingerprint, which is what the two screens are compared against.
      expect(find.text(identity.fingerprint), findsOneWidget);
    });

    testWidgets('and syncing with it again sends the memory instead of a token', (tester) async {
      // **The assertion the feature exists for.** The second sync must present the remembered key
      // and *no pairing code*: a token in the ticket would mean the reader had typed one, and the
      // point of learning a key is that they never have to again.
      final identity = await DeviceIdentity.generate();
      final fake = await _pump(
        tester,
        cellar: await _cellar(tester),
        identity: identity,
      );
      fake.joinOutcome = const ExchangeOutcome(
        merged: 0,
        sent: 3,
        peerName: 'laptop',
        peerIdentity: 'THE-LAPTOP-KEY',
      );

      await tester.enterText(find.byKey(const ValueKey('sync-code')), fake.ticket.encode());
      await tester.tap(find.text('连接并同步'));
      await tester.pump();
      await tester.pump();

      fake.calls.clear();
      // **Scrolled to first.** The remembered-devices block is below the two ways to start, and in an
      // 800x600 test viewport the button is off the bottom of the scroll view -- so the tap landed on
      // nothing and the assertion failed as an empty call list. `tap` does not scroll for you, and
      // the warning it prints in that case is easy to read past.
      await tester.ensureVisible(find.text('再同步一次'));
      await tester.pump();
      await tester.tap(find.text('再同步一次'));
      await tester.pump();
      await tester.pump();

      expect(fake.calls, ['join']);
      expect(fake.joinedExpecting, 'THE-LAPTOP-KEY');
      expect(fake.joinedWith!.token, isEmpty, reason: 'no code was typed, and none is needed');
      expect(fake.joinedWith!.host, '192.168.1.5');
      expect(fake.joinedWith!.port, 47821);
      expect(fake.joinedAs, identity, reason: 'and this device still offers its own key');
    });
  });

  group('what a share carries is chosen, and the choice reaches the exchange', () {
    testWidgets('with one shelf there is no chooser, because it would decide nothing', (tester) async {
      // **Section 12.3 already refuses a shelf chooser over a single shelf**, calling it furniture,
      // and the same argument holds here: a control whose options do nothing teaches a reader that
      // controls do nothing. The mechanism is finished underneath either way.
      final fake = await _pump(tester, cellar: await _cellar(tester, [
        StockEvents.bottleAdded(
          hlc: Hlc(physicalMillis: 1, counter: 0, nodeId: 'test'),
          bottleId: 'b1',
          sku: 'gin',
          volume: Volume.fromMillilitres(700),
        ),
        ShelfEvents.bottlePlaced(
          hlc: Hlc(physicalMillis: 2, counter: 0, nodeId: 'test'),
          bottleId: 'b1',
          shelfId: 'bar',
          posXPermille: 100,
          posYPermille: 100,
        ),
      ]));

      // **Dragged into view, not merely "ensured".** The token field the reader may fill in sits above this
      // button, and on a page that already has a shelf chooser that is enough to push it to the very edge --
      // where `ensureVisible` stops, the tap misses by a few pixels, and the failure reads as
      // "the source was the plain log" rather than "nothing was tapped". `dragUntilVisible` moves it clear of
      // the edge.
      await tester.dragUntilVisible(
        find.text('显示配对码'),
        find.byType(Scrollable).first,
        const Offset(0, -120),
      );
      await tester.pump();
      await tester.tap(find.text('显示配对码'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text(Copy.syncScope.primary.text), findsNothing);
      expect(capturedSources.single, isA<EventLog>(), reason: 'the log itself, unscoped');
      fake.peer.complete(const ExchangeOutcome(merged: 0, sent: 0));
      await tester.pump();
    });

    testWidgets('with two shelves one can be chosen, and the exchange reads through it', (tester) async {
      final fake = await _pump(tester, cellar: await _cellar(tester, _twoShelves()));

      // The chooser appears, and offering the whole cellar is one of its options -- not a hidden
      // default, because "which Bar" is a decision and a default is not a decision.
      expect(find.text(Copy.syncScope.primary.text), findsOneWidget);
      expect(find.text(Copy.syncScopeAll.primary.text), findsOneWidget);
      expect(find.text('bar'), findsOneWidget);

      // **The chip is pressed through its callback for the same reason the button is.** Both sit in a section
      // that grew a token field, and in this test's page they end up where a coordinate tap does not reach --
      // which showed up as "the source was the plain log", a failure that names neither the chip nor the miss.
      final shelfChip = tester.widget<ChoiceChip>(find.byKey(const ValueKey('scope-bar')));
      shelfChip.onSelected!(true);
      await tester.pump();

      // **Dragged into view, not merely "ensured".** The token field the reader may fill in sits above this
      // button, and on a page that already has a shelf chooser that is enough to push it to the very edge --
      // where `ensureVisible` stops, the tap misses by a few pixels, and the failure reads as
      // "the source was the plain log" rather than "nothing was tapped". `dragUntilVisible` moves it clear of
      // the edge.
      await tester.dragUntilVisible(
        find.text('显示配对码'),
        find.byType(Scrollable).first,
        const Offset(0, -120),
      );
      await tester.pump();
      await tester.tap(find.text('显示配对码'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      final source = capturedSources.last;
      expect(source, isA<ScopedSyncSource>());
      expect((source as ScopedSyncSource).scope.shelfId, 'bar');
      fake.peer.complete(const ExchangeOutcome(merged: 0, sent: 0));
      await tester.pump();
    });
  });
}

/// Two shelves with one bottle on each, so a scope has something to choose between.
List<Event> _twoShelves() {
  var tick = 10;
  Hlc at() => Hlc(physicalMillis: tick++, counter: 0, nodeId: 'test');
  return [
    StockEvents.bottleAdded(
      hlc: at(),
      bottleId: 'gin1',
      sku: 'gin',
      volume: Volume.fromMillilitres(700),
    ),
    ShelfEvents.bottlePlaced(
      hlc: at(),
      bottleId: 'gin1',
      shelfId: 'bar',
      posXPermille: 100,
      posYPermille: 100,
    ),
    StockEvents.bottleAdded(
      hlc: at(),
      bottleId: 'wine1',
      sku: 'wine',
      volume: Volume.fromMillilitres(750),
    ),
    ShelfEvents.bottlePlaced(
      hlc: at(),
      bottleId: 'wine1',
      shelfId: 'back',
      posXPermille: 300,
      posYPermille: 100,
    ),
  ];
}


/// The copy language pinned to Chinese for this file, so that assertions written against the authored
/// sentences do not depend on the platform locale of the machine running the tests.
class _FixedLocale extends LocaleSettingsNotifier {
  _FixedLocale(this._initial);

  final LocaleSettings _initial;

  @override
  LocaleSettings build() => _initial;
}
