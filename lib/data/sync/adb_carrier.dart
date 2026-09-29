import 'dart:io';

/// **The USB cable as a network, without pretending it is one.**
///
/// A phone plugged into a desktop can be reached two ways, and they are different things (10.2.0.5):
///
/// * **Tethering** makes the phone an interface -- `rndis0` or `usb0` -- and then it is an ordinary LAN with an
///   ordinary address. That is already classified as [SyncLink.usb] and needs nothing new.
/// * **ADB forwarding** leaves the interfaces alone and asks the *cable* to carry a TCP port: `adb forward
///   tcp:H tcp:D` makes `127.0.0.1:H` on this machine reach port `D` on the phone. No address on either
///   network, no wireless, nothing to break when the Wi-Fi is a hotel's.
///
/// This file is the second one, and it is the only carrier in this application that needs a tool from outside
/// it. **That is the honest cost and it is why nothing here is automatic**: `adb` is part of the Android
/// platform tools, a developer has it and a reader does not, so the screen offers this when the tool is present
/// and says plainly that it is missing when it is not, rather than failing at the end of a handshake.
///
/// ## What it will not do
///
/// It does not install anything, does not run `adb shell`, and does not touch a device it was not asked about.
/// The only command it runs is `forward` (and `forward --remove`), because that is the whole mechanism: a port
/// on this machine pointed at a port on that one. Everything above it -- the handshake, the key, the scope --
/// is the same code the wireless path uses, which is the point of a transport.

/// Runs a command and answers with what came back.
///
/// An injectable function rather than a direct `Process.run`, for one reason: **a test cannot have a phone
/// plugged into it**, and a carrier whose only untested path is the one that talks to a device is a carrier
/// nobody can trust. The tests pass a recorder and assert the exact command line.
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

Future<ProcessResult> _realRunner(String executable, List<String> arguments) =>
    Process.run(executable, arguments);

/// What the cable can offer right now.
enum AdbAvailability {
  /// The tool answered and there is at least one device on the other end.
  ready,

  /// `adb` is not installed, or not on this machine's path. The common case for a reader.
  noTool,

  /// The tool is there and no device is attached -- or the device is there and has not authorised this
  /// machine, which `adb devices` reports as `unauthorized` and which is a different sentence for the reader.
  noDevice,
}

/// What [AdbCarrier.inspect] found.
final class AdbStatus {
  const AdbStatus(this.availability, {this.detail = '', this.devices = const []});

  final AdbAvailability availability;

  /// The tool's own words, for a screen that wants to show them rather than summarise them.
  final String detail;

  /// The serials `adb devices` listed.
  final List<String> devices;

  String get sentence => switch (availability) {
    AdbAvailability.ready => 'adb is here, with ${devices.length} device(s)',
    AdbAvailability.noTool => 'adb is not installed on this machine',
    AdbAvailability.noDevice => detail.isEmpty
        ? 'adb is here and no device is attached'
        : 'adb is here and no device is usable: $detail',
  };
}

/// The result of asking the cable to carry a port.
final class AdbForward {
  const AdbForward({required this.hostPort, required this.devicePort, required this.address});

  final int hostPort;
  final int devicePort;

  /// Where to connect on **this** machine: a loopback address, because the datagrams never leave the cable.
  final String address;

  /// What the other side's ticket should say, so the reader can type it where they would type an address.
  String get hostAndPort => '$address:$hostPort';
}

/// What went wrong, in the reader's words, when [AdbCarrier.forward] refused.
final class AdbRefusal {
  const AdbRefusal(this.reason, {this.detail = ''});

  final String reason;
  final String detail;

  String get sentence => detail.isEmpty ? reason : '$reason ($detail)';
}

/// The carrier.
final class AdbCarrier {
  const AdbCarrier({ProcessRunner? run, this.executable = 'adb'})
    : _run = run ?? _realRunner;

  final ProcessRunner _run;

  /// The tool's name, so a build on a machine where it is called something else can say so.
  final String executable;

  /// **Is there a cable worth offering?** Two commands, because "the tool is missing" and "no phone is
  /// plugged in" are different sentences and only one of them is worth acting on.
  Future<AdbStatus> inspect() async {
    final String version;
    try {
      final result = await _run(executable, const ['version']);
      if (result.exitCode != 0) {
        return AdbStatus(
          AdbAvailability.noTool,
          detail: '${result.stderr}'.trim(),
        );
      }
      version = '${result.stdout}'.trim();
    } on ProcessException catch (error) {
      // The tool is not on the path at all: `ProcessException` rather than a non-zero exit.
      return AdbStatus(AdbAvailability.noTool, detail: error.message);
    } on Object catch (error) {
      return AdbStatus(AdbAvailability.noTool, detail: '$error');
    }

    try {
      final devices = await _run(executable, const ['devices']);
      final lines = '${devices.stdout}'.split('\n');
      final serials = <String>[];
      var unauthorized = 0;
      for (final line in lines.skip(1)) {
        final text = line.trim();
        if (text.isEmpty) continue;
        final parts = text.split(RegExp(r'\s+'));
        if (parts.length < 2) continue;
        if (parts[1] == 'device') {
          serials.add(parts[0]);
        } else if (parts[1] == 'unauthorized') {
          unauthorized++;
        }
      }
      if (serials.isEmpty) {
        return AdbStatus(
          AdbAvailability.noDevice,
          detail: unauthorized > 0
              // Worth its own sentence: the fix is on the phone's screen, not on this machine.
              ? 'the device has not authorised this machine -- accept the prompt on the phone'
              : 'nothing is plugged in',
          devices: const [],
        );
      }
      return AdbStatus(AdbAvailability.ready, detail: version, devices: serials);
    } on Object catch (error) {
      return AdbStatus(AdbAvailability.noDevice, detail: '$error');
    }
  }

  /// **Points a loopback port on this machine at a port on the phone.**
  ///
  /// [hostPort] defaults to the device port, because the two being equal is the arrangement every caller in
  /// this application wants and one number is easier to keep right than two.
  Future<(AdbForward?, AdbRefusal?)> forward({
    required int devicePort,
    int? hostPort,
  }) async {
    final status = await inspect();
    if (status.availability != AdbAvailability.ready) {
      return (null, AdbRefusal('no device to forward to', detail: status.sentence));
    }

    final host = hostPort ?? devicePort;
    try {
      final result = await _run(executable, [
        'forward',
        'tcp:$host',
        'tcp:$devicePort',
      ]);
      if (result.exitCode != 0) {
        return (
          null,
          AdbRefusal('the cable refused the forward', detail: '${result.stderr}'.trim()),
        );
      }
      return (AdbForward(hostPort: host, devicePort: devicePort, address: '127.0.0.1'), null);
    } on Object catch (error) {
      return (null, AdbRefusal('the forward could not be set up', detail: '$error'));
    }
  }

  /// Takes the forward away again, so a cable that was borrowed for one sync does not stay a network.
  Future<bool> unforward({required int hostPort}) async {
    try {
      final result = await _run(executable, ['forward', '--remove', 'tcp:$hostPort']);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }
}

/// The port this application forwards: **the sync port**, because what is on the other end of the cable is the
/// same listener the wireless path talks to.
const int defaultAdbDevicePort = 48123;
