import 'dart:io';

import 'package:hollow_court/data/event_log.dart';
import 'package:hollow_court/data/sync/socket_transport.dart';
import 'package:hollow_court/domain/events/stock.dart';
import 'package:hollow_court/domain/sync/exchange.dart';
import 'package:hollow_court/domain/sync/pairing.dart';
import 'package:hollow_court/domain/units/quantity.dart';
import 'package:test/test.dart';

/// Everything below talks over a real loopback socket.
///
/// The algorithm was proved without one, on purpose -- but proving it without one says nothing
/// about whether this file frames bytes correctly, enforces its limit while reading, or turns a
/// refused connection into an outcome. Those are exactly the parts that only a real connection can
/// check, so `Socket.connect('127.0.0.1', <the port a listener actually got>)` is the whole point
/// of the file rather than an inconvenience.
///
/// The port comes from the listener and is never written down: a fixed port would make these tests
/// fail when something else on the machine already holds it, and would make them fail *differently*
/// on a busy machine than on an idle one.
void main() {
  late Directory home;
  final servers = <ServerSocket>[];

  setUp(() => home = Directory.systemTemp.createTempSync('hollow-sync'));

  tearDown(() async {
    for (final server in servers) {
      await server.close();
    }
    servers.clear();
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  Future<EventLog> cellar(String node, {int startMillis = 1000}) => EventLog.open(
    file: File('${home.path}/$node.ndjson'),
    nodeId: node,
    nowMillis: () => startMillis,
  );

  Future<void> addBottle(EventLog log, String id, {int millilitres = 1000}) => log.record(
    (hlc) => StockEvents.bottleAdded(
      hlc: hlc,
      bottleId: id,
      sku: 'gin-$id',
      volume: Volume.fromMillilitres(millilitres),
    ),
  );

  Future<ServerSocket> listening() async {
    final server = await listenForSync(address: InternetAddress.loopbackIPv4);
    servers.add(server);
    return server;
  }

  /// Runs both ends at once against a real listener, as a connection does.
  Future<(ExchangeOutcome, ExchangeOutcome)> meet({
    required EventLog left,
    required EventLog right,
    String token = 'shared',
    String expectedToken = 'shared',
    String leftName = 'phone',
    String rightName = 'laptop',
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final server = await listening();
    final ticket = PairingTicket(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      token: token,
      name: rightName,
    );

    final results = await Future.wait([
      syncWithTicket(
        ticket: ticket,
        source: left,
        localName: leftName,
        timeout: timeout,
      ),
      acceptForSync(
        server: server,
        source: right,
        localName: rightName,
        expectedToken: expectedToken,
        timeout: timeout,
      ),
    ]);
    return (results[0], results[1]);
  }

  group('two cellars meet over a real socket', () {
    test('each keeps its own pouring and gains the other', () async {
      // The case section 6 exists for, now actually travelling: both devices pour while apart, and
      // after one sync neither pour is lost. A merge that lost one would still leave both logs
      // non-empty, so the assertion is on the totals rather than on the arrivals.
      final phone = await cellar('phone');
      final laptop = await cellar('laptop');
      await addBottle(phone, 'p1', millilitres: 700);
      await addBottle(laptop, 'l1', millilitres: 500);

      final (fromPhone, fromLaptop) = await meet(left: phone, right: laptop);

      expect(fromPhone.succeeded, isTrue, reason: fromPhone.failure);
      expect(fromLaptop.succeeded, isTrue, reason: fromLaptop.failure);

      expect(phone.events, hasLength(2));
      expect(laptop.events, hasLength(2));
      expect(fromPhone.merged, 1);
      expect(fromLaptop.merged, 1);
      expect(fromPhone.sent, 1);
      expect(fromLaptop.sent, 1);

      // The same events on both sides, in the same order, which is what makes the two folds agree.
      expect(
        phone.events.map((event) => event.encode()),
        laptop.events.map((event) => event.encode()),
      );
    });

    test('the peer name arrives, so a screen can say which device this was', () async {
      final phone = await cellar('phone');
      final laptop = await cellar('laptop');
      await addBottle(phone, 'p1');
      await addBottle(laptop, 'l1');

      final (fromPhone, fromLaptop) = await meet(left: phone, right: laptop);

      expect(fromPhone.peerName, 'laptop');
      expect(fromLaptop.peerName, 'phone');
    });

    test('a second sync between the same two cellars moves nothing', () async {
      // The digest doing its job across a real connection: after one exchange the two agree, so the
      // next one is one frame each. Asserted on the outcome because the wire is not visible here.
      final phone = await cellar('phone');
      final laptop = await cellar('laptop');
      await addBottle(phone, 'p1');
      await addBottle(laptop, 'l1');

      await meet(left: phone, right: laptop);
      final (again, _) = await meet(left: phone, right: laptop);

      expect(again.merged, 0);
      expect(again.sent, 0);
      expect(again.peerReason, 'already in sync');
    });

    test('more events than one frame holds cross over a real socket', () async {
      // Past maxItemsPerFrame, so the readings frame and the events are both chunked. This is the
      // case that failed while readings were sent in a single frame, and it is the size a real
      // cellar reaches long before anyone notices.
      final phone = await cellar('phone');
      final laptop = await cellar('laptop');
      final total = 300;
      for (var i = 0; i < total; i++) {
        await addBottle(phone, 'p$i');
      }

      final (fromPhone, fromLaptop) = await meet(left: phone, right: laptop);

      expect(fromPhone.succeeded, isTrue, reason: fromPhone.failure);
      expect(fromPhone.sent, total);
      expect(fromLaptop.merged, total);
      expect(laptop.events, hasLength(total));
      expect(phone.events, hasLength(total));
    });

    test('an empty cellar and a full one converge', () async {
      final phone = await cellar('phone');
      final laptop = await cellar('laptop');
      await addBottle(phone, 'p1');
      await addBottle(phone, 'p2');

      final (fromPhone, fromLaptop) = await meet(left: phone, right: laptop);

      expect(fromPhone.sent, 2);
      expect(fromPhone.merged, 0);
      expect(fromLaptop.merged, 2);
      expect(laptop.events, hasLength(2));
    });
  });

  group('the token is the gate, and it is checked over a real connection', () {
    test('a wrong token leaves both cellars untouched', () async {
      final phone = await cellar('phone');
      final laptop = await cellar('laptop');
      await addBottle(phone, 'p1');
      await addBottle(laptop, 'l1');

      final (fromPhone, fromLaptop) = await meet(
        left: phone,
        right: laptop,
        token: 'the-wrong-one',
        expectedToken: 'the-right-one',
      );

      expect(fromPhone.succeeded, isFalse);
      expect(fromLaptop.succeeded, isFalse);
      expect(fromPhone.failure, contains('pairing code'));

      expect(phone.events, hasLength(1));
      expect(laptop.events, hasLength(1));
    });
  });

  test('**a code with a hostname in it is refused, because there may be no name service**', () async {
    // The closed-network guarantee at the point where it could be lost. `Socket.connect` takes a `String`
    // and resolves it when it is a hostname, so a code carrying one would send this process to a resolver
    // -- and a resolver is the outside world. The owner's framing is exact: this is a traditional VPN in
    // the sense that it never talks to the internet, the way a hospital's internal network does.
    //
    // So the name is refused before a socket exists, with a sentence that says why rather than a
    // resolution failure that does not. Two devices on one network already know where each other are.
    final log = await cellar('hostname-test');
    final outcome = await syncWithTicket(
      ticket: const PairingTicket(host: 'laptop.local', port: 49000, token: 'x', name: 'laptop'),
      source: log,
      localName: 'phone',
    );

    expect(outcome.succeeded, isFalse);
    expect(outcome.failure, contains('not an IP address'));
    expect(outcome.failure, contains('name service'));
  });

  group('a connection that is not a sync is refused without hanging', () {
    test('junk on the port ends the exchange with a reason', () async {
      // Not hypothetical: a port scanner, a browser pointed at the wrong thing, or a leftover client
      // from an earlier version all arrive here, and all of them must end in a sentence.
      final laptop = await cellar('laptop');
      await addBottle(laptop, 'l1');
      final server = await listening();

      final responder = acceptForSync(
        server: server,
        source: laptop,
        localName: 'laptop',
        expectedToken: 'shared',
        timeout: const Duration(seconds: 10),
      );

      final intruder = await Socket.connect(
        InternetAddress.loopbackIPv4.address,
        server.port,
      );
      intruder.write('GET / HTTP/1.1\r\nHost: localhost\r\n\r\n');
      await intruder.flush();

      final outcome = await responder;

      expect(outcome.succeeded, isFalse);
      expect(outcome.failure, isNotNull);
      expect(laptop.events, hasLength(1), reason: 'nothing should have been merged');
    });

    test('a peer that connects and says nothing hits the deadline', () async {
      // A connection that is open and silent must not hold the resource until the process ends.
      final laptop = await cellar('laptop');
      final server = await listening();

      final responder = acceptForSync(
        server: server,
        source: laptop,
        localName: 'laptop',
        expectedToken: 'shared',
        timeout: const Duration(milliseconds: 250),
      );

      final silent = await Socket.connect(
        InternetAddress.loopbackIPv4.address,
        server.port,
      );
      // Held open on purpose: the failure under test is a peer that connected successfully and then
      // said nothing, which is not the same as one that never arrived.
      addTearDown(silent.destroy);

      final outcome = await responder;

      expect(outcome.succeeded, isFalse);
      expect(outcome.failure, contains('stopped answering'));
    });

    test('a refused connection is an outcome and not an exception', () async {
      // Nothing is more ordinary on a network than the other device being asleep. The caller is a
      // button press, so this has to come back as something a screen can say.
      final phone = await cellar('phone');
      final server = await listening();
      final deadPort = server.port;
      await server.close();

      final outcome = await syncWithTicket(
        ticket: PairingTicket(
          host: InternetAddress.loopbackIPv4.address,
          port: deadPort,
          token: 'shared',
        ),
        source: phone,
        localName: 'phone',
        connectTimeout: const Duration(milliseconds: 500),
        timeout: const Duration(milliseconds: 500),
      );

      expect(outcome.succeeded, isFalse);
      expect(outcome.failure, contains('could not reach'));
    });
  });

  group('the ticket a listener hands out is reachable', () {
    test('it carries the port the operating system actually chose', () async {
      final server = await listening();

      final ticket = await ticketForListener(
        server,
        token: 'k7fq2m',
        name: 'laptop',
        host: '192.168.1.42',
      );

      expect(ticket.port, server.port);
      expect(ticket.port, greaterThan(0));
      expect(ticket.host, '192.168.1.42');
      expect(ticket.token, 'k7fq2m');
      expect(PairingTicket.parse(ticket.encode())!.port, server.port);
    });

    test('asking for the machine address answers or declines, but never throws', () async {
      // This machine may have no interface to offer, and that is a legitimate answer: the pairing
      // flow is a string that can be typed, so a null here is a fallback and not a failure.
      final address = await lanAddress();
      expect(address == null || address.isNotEmpty, isTrue);
    });
  });
}
