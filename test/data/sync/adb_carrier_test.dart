import 'dart:io';

import 'package:hollow_court/data/sync/adb_carrier.dart';
import 'package:test/test.dart';

/// **The ADB carrier, tested without a phone.**
///
/// The commands are recorded rather than run: a test cannot have a device plugged into it, and the one path
/// nobody can test is the one nobody can trust. What is asserted here is the **exact command line** and every
/// way the tool can decline -- missing, unplugged, unauthorised, refused.
void main() {
  ProcessResult ok(String stdout) => ProcessResult(0, 0, stdout, '');
  ProcessResult bad(int code, String stderr) => ProcessResult(code, code, '', stderr);

  /// A carrier over a recorded command line, with a per-command answer.
  (AdbCarrier, List<String>) carrier({
    required ProcessResult Function(String executable, List<String> arguments) answer,
  }) {
    final calls = <String>[];
    final instance = AdbCarrier(
      run: (executable, arguments) async {
        calls.add('$executable ${arguments.join(' ')}');
        if (arguments.isNotEmpty && arguments.first == 'version' && arguments.length == 1) {
          return answer(executable, arguments);
        }
        return answer(executable, arguments);
      },
    );
    return (instance, calls);
  }

  test('**a device on the other end is found, and the probe runs the two commands it needs**', () async {
    final (adb, calls) = carrier(
      answer: (executable, arguments) {
        if (arguments.first == 'version') return ok('Android Debug Bridge version 1.0.41');
        return ok('List of devices attached\nSERIAL0001\tdevice\n');
      },
    );
    final status = await adb.inspect();
    expect(status.availability, AdbAvailability.ready);
    expect(status.devices, ['SERIAL0001']);
    expect(status.sentence, contains('1 device'));
    expect(calls, ['adb version', 'adb devices']);
  });

  test('**a missing tool is its own answer, not a failure at the end of a handshake**', () async {
    final adb = AdbCarrier(
      run: (executable, arguments) async => throw ProcessException(executable, arguments, 'not found'),
    );
    final status = await adb.inspect();
    expect(status.availability, AdbAvailability.noTool);
    expect(status.sentence, contains('not installed'));

    final (forwarded, refusal) = await adb.forward(devicePort: 48123);
    expect(forwarded, isNull);
    expect(refusal!.sentence, contains('not installed'));
  });

  test('**an unauthorised phone gets the sentence that says where to fix it**', () async {
    // **A synthetic serial, not the handset this was written against.** A fixture written with a real device
    // identifier is a device identifier in a public repository.
    // The difference that matters: "nothing is plugged in" sends somebody to the cable, and "not authorised"
    // sends them to the phone's screen. One sentence for both would send half of them to the wrong place.
    final (adb, _) = carrier(
      answer: (executable, arguments) => arguments.first == 'version'
          ? ok('Android Debug Bridge version 1.0.41')
          : ok('List of devices attached\nSERIAL0001\tunauthorized\n'),
    );
    final status = await adb.inspect();
    expect(status.availability, AdbAvailability.noDevice);
    expect(status.sentence, contains('accept the prompt on the phone'));
  });

  test('**the forward is exactly one command, and it points at the sync port**', () async {
    final calls = <String>[];
    final adb = AdbCarrier(
      run: (executable, arguments) async {
        calls.add(arguments.join(' '));
        if (arguments.first == 'version') return ok('Android Debug Bridge version 1.0.41');
        if (arguments.first == 'devices') {
          return ok('List of devices attached\nSERIAL\tdevice\n');
        }
        return ok('');
      },
    );
    final (forward, refusal) = await adb.forward(devicePort: defaultAdbDevicePort);
    expect(refusal, isNull);
    expect(forward!.hostPort, defaultAdbDevicePort);
    expect(forward.address, '127.0.0.1', reason: 'the datagrams stay on the cable');
    expect(forward.hostAndPort, '127.0.0.1:48123');
    expect(calls, ['version', 'devices', 'forward tcp:48123 tcp:48123']);

    // And the forward can be taken away, so a borrowed cable does not stay a network.
    expect(await adb.unforward(hostPort: 48123), isTrue);
    expect(calls.last, 'forward --remove tcp:48123');
  });

  test('a forward the cable refuses comes back as a refusal with the tool\'s own words', () async {
    final adb = AdbCarrier(
      run: (executable, arguments) async {
        if (arguments.first == 'version') return ok('Android Debug Bridge version 1.0.41');
        if (arguments.first == 'devices') return ok('List of devices attached\nS\tdevice\n');
        return bad(1, 'error: cannot bind listener: Address already in use');
      },
    );
    final (forward, refusal) = await adb.forward(devicePort: 48123, hostPort: 50000);
    expect(forward, isNull);
    expect(refusal!.sentence, contains('Address already in use'));
  });

  test('only `forward` is ever run -- no shell, no install, nothing that changes the device', () async {
    // The carrier's promise in one assertion: the commands it can run are enumerated, so a future edit that
    // reaches for `adb shell` fails here rather than in somebody's phone.
    final calls = <List<String>>[];
    final adb = AdbCarrier(
      run: (executable, arguments) async {
        calls.add(arguments);
        if (arguments.first == 'version') return ok('Android Debug Bridge version 1.0.41');
        if (arguments.first == 'devices') return ok('List of devices attached\nS\tdevice\n');
        return ok('');
      },
    );
    await adb.inspect();
    await adb.forward(devicePort: 48123);
    await adb.unforward(hostPort: 48123);
    for (final arguments in calls) {
      expect(
        arguments.first,
        anyOf('version', 'devices', 'forward'),
        reason: 'the carrier only forwards ports: $arguments',
      );
    }
  });
}
