// Every verb the stock log can express, carried between two cellars over a real socket.
//
// WHY THIS FILE EXISTS SEPARATELY FROM THE OTHERS.
//
//   `exchange_test.dart`      proves the algorithm, on a `SyncSource` that is three methods
//   `socket_transport_test.dart` proves the framing, over loopback, with two events
//   `p3_acceptance_test.dart` proves the screens drive it, through a memory channel
//   **this one**              proves that no verb is quietly left behind
//
// The gap it closes is specific and was opened by this project's own work: a new stock op,
// `stock.bottle.removed`, was added to the domain, and the sync path is deliberately type-agnostic
// -- `missingFrom` asks about clocks and `merge` appends whatever arrives -- so nothing in the sync
// layer had to change for it to travel. **That is exactly the sort of claim that turns out to be
// false**, and the only honest way to hold it is to put every verb through one real connection and
// compare the two folds afterwards.
//
// So the fixture records one of everything: a bottle added with a price and a currency, a pour, a
// discard, a recount, a second bottle, and that second bottle retracted. Both devices then meet, and
// what is asserted is not "the bytes arrived" but "the two cellars agree about what happened" --
// the ledger's own numbers, the removed set, and the price series the chart draws.
import 'dart:io';

import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/data/sync/socket_transport.dart';
import 'package:hollow_court/data/sync/sync_service.dart';
import 'package:hollow_court/domain/events/price.dart';
import 'package:hollow_court/domain/sync/device_identity.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/sync/exchange.dart';
import 'package:hollow_court/domain/sync/pairing.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

void main() {
  late Directory home;
  final servers = <ServerSocket>[];
  // One clock per log, advanced by hand: an HLC built from a real clock would make these tests
  // depend on how fast the machine is, and the ordering is what is being tested.
  final ticks = <String, int>{};

  setUp(() => home = Directory.systemTemp.createTempSync('hollow-verbs'));

  tearDown(() async {
    for (final server in servers) {
      await server.close();
    }
    servers.clear();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Future<EventLog> cellar(String node) {
    ticks[node] = 1000;
    return EventLog.open(
      file: File('${home.path}/$node.ndjson'),
      nodeId: node,
      nowMillis: () => ticks[node] = ticks[node]! + 1,
    );
  }

  Future<ServerSocket> listening() async {
    final server = await listenForSync(address: InternetAddress.loopbackIPv4);
    servers.add(server);
    return server;
  }

  /// Both ends at once, with identities and expectations where a test needs them.
  Future<(ExchangeOutcome, ExchangeOutcome)> meetWithIdentities({
    required EventLog left,
    required EventLog right,
    required DeviceIdentity leftIdentity,
    required DeviceIdentity rightIdentity,
    String leftExpected = '',
    String rightExpected = '',
    String leftToken = 'shared',
    String rightToken = 'shared',
  }) async {
    final server = await listening();
    final ticket = PairingTicket(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      token: leftToken,
      name: 'laptop',
    );
    final results = await Future.wait([
      syncWithTicket(
        ticket: ticket,
        source: left,
        localName: 'phone',
        identity: leftIdentity,
        expectedIdentity: leftExpected,
      ),
      acceptForSync(
        server: server,
        source: right,
        localName: 'laptop',
        expectedToken: rightToken,
        identity: rightIdentity,
        expectedIdentity: rightExpected,
      ),
    ]);
    return (results[0], results[1]);
  }

  /// Both ends at once against a real listener, as a connection does.
  Future<(ExchangeOutcome, ExchangeOutcome)> meet({
    required EventLog left,
    required EventLog right,
  }) async {
    final server = await listening();
    final ticket = PairingTicket(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      token: 'shared',
      name: 'laptop',
    );

    final results = await Future.wait([
      syncWithTicket(ticket: ticket, source: left, localName: 'phone'),
      acceptForSync(
        server: server,
        source: right,
        localName: 'laptop',
        expectedToken: 'shared',
      ),
    ]);
    return (results[0], results[1]);
  }

  test('every stock verb crosses a real connection, and both folds agree', () async {
    final phone = await cellar('phone');
    final laptop = await cellar('laptop');

    // ---- the phone's cellar, one of everything -------------------------------------------
    await phone.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'kept',
        sku: 'gin',
        volume: Volume.fromMillilitres(700),
        priceMinor: 12000,
        currency: 'CNY',
        purchasedAtMillis: 1,
      ),
    );
    await phone.record(
      (hlc) => StockEvents.bottleConsumed(
        hlc: hlc,
        bottleId: 'kept',
        volume: Volume.fromMillilitres(45),
      ),
    );
    await phone.record(
      (hlc) => StockEvents.bottleDiscarded(
        hlc: hlc,
        bottleId: 'kept',
        volume: Volume.fromMillilitres(10),
      ),
    );
    await phone.record(
      (hlc) => StockEvents.bottleRecounted(
        hlc: hlc,
        bottleId: 'kept',
        volume: Volume.fromMillilitres(500),
      ),
    );
    await phone.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'mistake',
        sku: 'rye',
        volume: Volume.fromMillilitres(750),
      ),
    );
    // The verb this file was written for.
    await phone.record(
      (hlc) => StockEvents.bottleRemoved(hlc: hlc, bottleId: 'mistake'),
    );

    // ---- the laptop's own bottle, so the exchange is two-way ------------------------------
    await laptop.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'other',
        sku: 'vermouth',
        volume: Volume.fromMillilitres(1000),
      ),
    );

    final (fromPhone, fromLaptop) = await meet(left: phone, right: laptop);

    expect(fromPhone.succeeded, isTrue, reason: fromPhone.failure);
    expect(fromLaptop.succeeded, isTrue, reason: fromLaptop.failure);

    // ---- the same events, on both sides --------------------------------------------------
    final phoneClocks = phone.clocks.map((hlc) => hlc.toString()).toSet();
    final laptopClocks = laptop.clocks.map((hlc) => hlc.toString()).toSet();
    expect(phoneClocks, laptopClocks);
    expect(phone.events, hasLength(7), reason: 'six of the phone\'s plus the laptop\'s');
    expect(laptop.events, hasLength(7));

    // ---- and the same conclusions --------------------------------------------------------
    for (final log in [phone, laptop]) {
      final side = log.clock.nodeId;
      final stock = log.stock;

      expect(stock.unknownBottles, isEmpty, reason: side);
      expect(stock.duplicateAdds, isEmpty, reason: side);

      // The retracted line left no bottle behind, on either side.
      expect(stock.bottle('mistake'), isNull, reason: '$side kept a retracted bottle');
      expect(stock.removedBottleIds, {'mistake'}, reason: side);

      // The recount is the number that stands: 500 ml, not 700 - 45 - 10.
      expect(stock.bottle('kept')!.remaining, Volume.fromMillilitres(500), reason: side);
      expect(stock.bottle('kept')!.consumed, Volume.fromMillilitres(45), reason: side);
      expect(stock.bottle('kept')!.discarded, Volume.fromMillilitres(10), reason: side);

      expect(stock.bottleCount, 2, reason: '$side counts kept and other only');
      expect(stock.remainingTotal, Volume.fromMillilitres(1500), reason: side);

      // The chart is drawn from a different fold over the same events, and it has to agree with
      // the shelf -- which is the whole reason `removedBottleIds` exists.
      final points = pricePointsOf(
        log.events,
        removedBottles: stock.removedBottleIds,
      );
      expect(points, hasLength(1), reason: '$side: the kept bottle, and not the retracted one');
      expect(points.single.paid.currency.code, 'CNY', reason: side);
    }
  });

  test('the second sync needs no code, because the key was learned by the first', () async {
    // **The whole point of a long-term key, over a real socket.** The first meeting is authenticated
    // by the pairing code, exactly as section 10.3 says; each side learns the other's key during it;
    // the second meeting is authenticated by the key alone, so nobody has to stand at two screens
    // reading six characters again.
    //
    // A device that is not the one remembered is refused in the same test, because a key that
    // recognises anybody is not a key.
    final phone = await cellar('phone');
    final laptop = await cellar('laptop');
    final phoneIdentity = await DeviceIdentity.generate();
    final laptopIdentity = await DeviceIdentity.generate();

    await phone.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'p1',
        sku: 'gin',
        volume: Volume.fromMillilitres(700),
      ),
    );

    // ---- first meeting, with the code ----------------------------------------------------
    final (first, second) = await meetWithIdentities(
      left: phone,
      right: laptop,
      leftIdentity: phoneIdentity,
      rightIdentity: laptopIdentity,
    );

    expect(first.succeeded, isTrue, reason: first.failure);
    expect(second.succeeded, isTrue, reason: second.failure);
    expect(first.peerIdentity, laptopIdentity.publicKey, reason: 'the phone learned the laptop');
    expect(second.peerIdentity, phoneIdentity.publicKey, reason: 'and the laptop learned the phone');
    expect(laptop.stock.bottle('p1'), isNotNull, reason: 'and the bottle crossed');

    // ---- second meeting, with no code at all --------------------------------------------
    await phone.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'p2',
        sku: 'rye',
        volume: Volume.fromMillilitres(750),
      ),
    );

    final (again, back) = await meetWithIdentities(
      left: phone,
      right: laptop,
      leftIdentity: phoneIdentity,
      rightIdentity: laptopIdentity,
      leftExpected: laptopIdentity.publicKey,
      rightExpected: phoneIdentity.publicKey,
      leftToken: '',
      rightToken: '',
    );

    expect(again.succeeded, isTrue, reason: again.failure);
    expect(back.succeeded, isTrue, reason: back.failure);
    // The phone is the LEFT end and it is the one that had something new, so it *sent* rather than
    // merged -- the second time in this session that I have asserted a count on the wrong end. The
    // counts are directional and the direction depends on who recorded what, not on who dialled.
    expect(again.sent, 1, reason: 'the phone handed over the bottle that was waiting');
    expect(back.merged, 1, reason: 'and the laptop took it in');
    expect(laptop.stock.bottle('p2'), isNotNull);

    // ---- and an impostor is refused, over the same real socket ---------------------------
    final stranger = await DeviceIdentity.generate();
    final (fromStranger, fromLaptop) = await meetWithIdentities(
      left: phone,
      right: laptop,
      leftIdentity: stranger,
      rightIdentity: laptopIdentity,
      leftExpected: laptopIdentity.publicKey,
      rightExpected: phoneIdentity.publicKey,
      leftToken: '',
      rightToken: '',
    );

    expect(fromStranger.succeeded, isFalse);
    expect(fromLaptop.succeeded, isFalse);
    // **The message distinguishes two different mistakes.** A peer that presents the code and the wrong
    // key gets 这不是本机记住的那台设备; a peer that presents neither the code nor a known key gets 对方没有
    // 证明它可以连接. This stranger is the second kind -- it had no code at all -- and the distinction is
    // there so a reader knows whether to check what they typed or to pair the device again.
    expect(fromLaptop.failure, 'the other device did not prove that it may connect');
  });

  test('a host accepts a remembered key in place of the code it is showing', () async {
    // **The test that was missing, and the three defects it would have caught at once.** The feature
    // "the second sync needs no code" was wired through the controller, asserted by a screen test against
    // a *fake* service, and **broken end to end** -- found by running two real processes against each
    // other with `tool/sync_probe.dart`, which is the only thing that could have found it:
    //
    //   1. the host refused the peer in the handshake, because it still demanded the code;
    //   2. the host's key check compared against *one* expected key, and a host has a list;
    //   3. the exchange then refused the connection with 配对码不对, because a key-authenticated peer
    //      has no token to put in its hello.
    //
    // All three are fixed, and this is what holds them: the host takes the code (so a new device can
    // still pair) **and** the keys it remembers, and the joiner sends no token at all.
    final phone = await cellar('phone');
    final laptop = await cellar('laptop');
    final phoneIdentity = await DeviceIdentity.generate();
    final laptopIdentity = await DeviceIdentity.generate();

    await phone.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'p1',
        sku: 'gin',
        volume: Volume.fromMillilitres(700),
      ),
    );
    await laptop.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'l1',
        sku: 'rye',
        volume: Volume.fromMillilitres(750),
      ),
    );

    // ---- first meeting: the host shows a code and requires it --------------------------
    final server = await listening();
    final first = await Future.wait([
      syncWithTicket(
        ticket: PairingTicket(
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          token: 'shared',
          name: 'laptop',
        ),
        source: laptop,
        localName: 'phone',
        identity: laptopIdentity,
      ),
      acceptForSync(
        server: server,
        source: phone,
        localName: 'phone',
        expectedToken: 'shared',
        identity: phoneIdentity,
      ),
    ]);
    expect(first.every((outcome) => outcome.succeeded), isTrue,
        reason: first.map((o) => o.failure).join(', '));

    // ---- second meeting: the joiner has NO token, and the host accepts its key ----------
    await phone.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'p2',
        sku: 'scotch',
        volume: Volume.fromMillilitres(700),
      ),
    );
    final again = await listening();
    final second = await Future.wait([
      syncWithTicket(
        // An empty token: this is the whole point. A code is whatever the host is showing right now,
        // and nobody typed it.
        ticket: PairingTicket(
          host: InternetAddress.loopbackIPv4.address,
          port: again.port,
          token: '',
          name: 'laptop',
        ),
        source: laptop,
        localName: 'phone',
        identity: laptopIdentity,
        expectedIdentity: phoneIdentity.publicKey,
      ),
      acceptForSync(
        server: again,
        source: phone,
        localName: 'phone',
        // The code it is showing, which nobody will present...
        expectedToken: mintPairingToken(),
        // ...and the devices it has met, one of which is arriving.
        acceptedIdentities: {laptopIdentity.publicKey},
        identity: phoneIdentity,
      ),
    ]);

    expect(
      second.every((outcome) => outcome.succeeded),
      isTrue,
      reason: 'a remembered key is a way in: ${second.map((o) => o.failure).join(', ')}',
    );
    expect(laptop.stock.bottle('p2'), isNotNull, reason: 'and the new bottle crossed');
  });

  test('a host refuses a device it does not know and that has no code', () async {
    // The other half, and it is the security-relevant one: accepting a remembered key must not become
    // accepting anybody. A stranger with neither the code nor a learned key is refused, and the refusal
    // says which of the two it lacked.
    final host = await cellar('phone');
    final hostIdentity = await DeviceIdentity.generate();
    final stranger = await DeviceIdentity.generate();

    final server = await listening();
    final outcomes = await Future.wait([
      syncWithTicket(
        ticket: PairingTicket(
          host: InternetAddress.loopbackIPv4.address,
          port: server.port,
          token: '',
          name: 'phone',
        ),
        source: await cellar('stranger'),
        localName: 'stranger',
        identity: stranger,
        expectedIdentity: hostIdentity.publicKey,
      ),
      acceptForSync(
        server: server,
        source: host,
        localName: 'phone',
        expectedToken: mintPairingToken(),
        acceptedIdentities: {(await DeviceIdentity.generate()).publicKey},
        identity: hostIdentity,
      ),
    ]);

    expect(outcomes.any((outcome) => outcome.succeeded), isFalse);
    expect(
      outcomes.map((outcome) => outcome.failure).join(' | '),
      contains('not a device this one remembers'),
    );
  });

  test('a retraction that arrives on its own still lands', () async {
    // The retraction is the newest verb, so it is the one a peer running an older build would send
    // first, and it is the one whose parse path is unusual: it carries no `volumeMicrolitres`, and
    // the parser used to require that key before it looked at anything else. A retraction that
    // arrived alone would be dropped by such a parser and the bottle would come back on the fold.
    final phone = await cellar('phone');
    final laptop = await cellar('laptop');

    await laptop.record(
      (hlc) => StockEvents.bottleAdded(
        hlc: hlc,
        bottleId: 'gone',
        sku: 'gin',
        volume: Volume.fromMillilitres(700),
      ),
    );
    // A separate exchange, so the two halves are not in the same frame batch as the add.
    await meet(left: phone, right: laptop);
    expect(phone.stock.bottle('gone'), isNotNull);

    await laptop.record(
      (hlc) => StockEvents.bottleRemoved(hlc: hlc, bottleId: 'gone'),
    );
    // `meet` returns the LEFT end's outcome first, and the left end is the phone -- which is the
    // side receiving here. My first version asserted the count on the laptop's outcome and got 0,
    // correctly: the laptop wrote the retraction, so nothing arrived for it to merge.
    final (phoneSide, laptopSide) = await meet(left: phone, right: laptop);

    expect(phoneSide.succeeded, isTrue, reason: phoneSide.failure);
    expect(phoneSide.merged, 1, reason: 'the retraction is the one new event');
    expect(laptopSide.merged, 0, reason: 'the writer has nothing to receive');
    expect(phone.stock.bottle('gone'), isNull,
        reason: 'the phone was told, and the bottle is gone there too');
    expect(phone.stock.removedBottleIds, {'gone'});
  });

  // ---------------------------------------------------------------------------------------------
  // The reachable listener: a device that is tapped, rather than a device showing a code.
  //
  // **A regression test for the two defects this feature had on real machines**, both reported by a person
  // holding a phone rather than by a failing test:
  //
  //   * a listener that answered once and then died with `Bad state: Stream was already listened to`, because a
  //     `ServerSocket` is a single-subscription stream and the first version accepted with `server.first` again;
  //   * a peer remembered with a key and **nowhere to dial**, because only the accepted socket knows the
  //     address the connection came from.
  test('**a listener that is tapped answers again, and says where the peer was**', () async {
    final guest = await cellar('phone');
    final host = await cellar('laptop');
    final guestIdentity = await DeviceIdentity.generate();
    final hostService = SocketSyncService(source: host, name: 'laptop');
    final port = await hostService.openForRequests(
      identity: await DeviceIdentity.generate(),
      acceptedIdentities: const {},
    );
    // **The address the listener actually bound to**, which is *not* loopback: `openForRequests` prefers the LAN
    // address for the reason `listenForLanSync` documents, and a test that dialled 127.0.0.1 got a refusal rather
    // than a listener. The runner has the same address, so this is a loopback test that happens to travel through
    // the real interface -- which is also what a neighbour's tap does.
    final where = await lanAddress() ?? InternetAddress.loopbackIPv4.address;

    // **Two requests, one listener, and both sides started together.** The first version of this test awaited the
    // host's answer first, which is a deadlock rather than a failure: nobody connects until the guest is started.
    for (var round = 1; round <= 2; round++) {
      final results = await Future.wait([
        hostService.awaitRequest(confirmComparison: (_) async => true),
        syncWithTicket(
          ticket: PairingTicket(
            host: where,
            port: port,
            token: '',
            name: 'laptop',
          ),
          source: guest,
          localName: 'phone',
          identity: guestIdentity,
        ),
      ]);
      expect(results[0].failure, isNull, reason: 'round $round was answered');
      expect(results[1].failure, isNull, reason: 'round $round reached the host');
      expect(
        results[0].peerAddress,
        where,
        reason: 'what 再同步一次 dials comes off the socket that accepted the connection',
      );
      // **And the identity comes with it in both rounds**, including the second -- which is the one where there is
      // nothing to merge and where a version that only stamped identities on the busy path remembered nobody.
      expect(results[0].peerIdentity, isNotEmpty, reason: 'the key to remember came with it');
    }

    await hostService.closeForRequests();
  });
}
