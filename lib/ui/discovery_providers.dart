import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sync/discovery_socket.dart';
import '../domain/sync/device_identity.dart';
import '../domain/sync/discovery.dart';
import 'sync_identity.dart';
import 'sync_names.dart';

/// **The port this device is reachable on right now, or null when it is not.**
///
/// The announcement carries it, and that is the whole reason it is a value on its own: §10.3.2 asks that a tap
/// in 附近的设备 connect, which is only possible if the port a device announces is the port something is
/// listening on. Until this existed the announcement named the constant `defaultDiscoveryPort + 1` and nothing
/// bound it, so every announcement was a promise with no socket behind it.
///
/// **A provider rather than a field of the sync state**, because the two writers and the reader are in three
/// places -- the listener opens and closes in the controller, the announcement is built here -- and a port that
/// could be lost by a state rebuild would be an announcement that lies for three seconds at a time.
final reachablePortProvider = NotifierProvider<ReachablePort, int?>(ReachablePort.new);

/// Holds the port [LanDiscovery] should announce, and nothing else.
final class ReachablePort extends Notifier<int?> {
  @override
  int? build() => null;

  /// Publishes a new port, or null when this device is no longer reachable.
  void publish(int? port) {
    if (state != port) state = port;
  }
}

/// **The devices this one can hear, while somebody is looking.**
///
/// The owner asked for the discovery that makes "see a name, tap it, sync" work, and the domain for it was
/// finished long before anything sent a datagram -- so this is the piece that turns a tested roster into a
/// list on a screen.
///
/// ## Discovery belongs to the screen, and that is the decision
///
/// [decision] **Opened when this provider is watched and closed when it stops being watched**, which in
/// practice means the sync screen. The alternative -- announcing from launch -- buys a device that is
/// discoverable while nobody is looking, and on Android it costs a **foreground service** to keep announcing
/// after the screen sleeps, which is a standing notification and a permission conversation for a feature
/// nobody asked to run in the background. Section 10.2.0.1 says a mode is a promise rather than a preference:
/// the promise here is "while this screen is open, your devices can find each other", and it is one that can
/// be kept without a service.
///
/// **The same promise was extended to being reachable** (§10.3.2): the screen opens a listener, the
/// announcement carries its port, and a neighbour's tap arrives at a socket that exists. The listener is opened
/// by the screen rather than by this provider, because the screen is what knows when it is being looked at and
/// it outlives the sub-views this provider is torn down by.
///
/// ## What the list is allowed to say
///
/// Name, short fingerprint, and whether this machine has met the device before. **Nothing on the screen is
/// trusted**: an announcement is a claim, the fingerprint only selects a row in the store of already-paired
/// devices, and the connection still proves the key during the handshake. A device that announces no
/// fingerprint is shown as new rather than hidden -- it is a stranger, and a stranger is information.
final discoveredDevicesProvider = StreamProvider.autoDispose<List<DiscoveredDevice>>((ref) async* {
  final identity = ref.watch(syncIdentityProvider).value?.identity;
  final names = ref.watch(syncNamesProvider).value;
  // Without an identity there is nothing to announce and no fingerprint for a peer to recognise, so the list
  // is empty rather than wrong.
  if (identity == null) {
    yield const [];
    return;
  }

  // **The port the listener holds, or nothing announces at all.** A device with no listener is a device a tap
  // cannot reach, and an announcement that said otherwise would send a neighbour's request into a closed port --
  // which is exactly the failure this replaced. `yield const []` rather than an announcement with a placeholder
  // port: being invisible for the moment it takes the listener to bind is honest, being reachable-looking is not.
  final port = ref.watch(reachablePortProvider);
  if (port == null) {
    yield const [];
    return;
  }

  final trusted = ref.watch(syncIdentityProvider).value?.trusted ?? const <TrustedDevice>[];
  final remembered = {for (final device in trusted) DeviceIdentity.fingerprintOf(device.publicKey)};

  final discovery = await LanDiscovery.start(
    announce: DiscoveryAnnounce(
      deviceName: names?.deviceName ?? 'this device',
      fingerprint: identity.fingerprint,
      // The port a peer will connect to: **the listener's own**, not a constant. This is the address the
      // announcement is *for*, and it is the reason a tap can connect at all.
      port: port,
      version: '1.0.0',
    ),
  );

  final roster = DeviceRoster();
  final updates = StreamController<void>();
  final subscription = discovery.announces.listen((heard) {
    roster.observe(
      heard.announce,
      address: heard.address,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
      rememberedFingerprints: remembered,
    );
    if (!updates.isClosed) updates.add(null);
  });

  // Expiry on a timer as well as on arrival: a device that stops announcing must *leave* the list, and no
  // datagram arrives to say so. A third of the roster's expiry keeps the list at most that stale.
  final sweeper = Timer.periodic(const Duration(seconds: 4), (_) {
    if (roster.expire(DateTime.now().millisecondsSinceEpoch) && !updates.isClosed) {
      updates.add(null);
    }
  });

  try {
    yield roster.devices;
    await for (final _ in updates.stream) {
      yield roster.devices;
    }
  } finally {
    sweeper.cancel();
    await subscription.cancel();
    await updates.close();
    await discovery.stop();
  }
});

/// Starts announcing immediately rather than waiting for the first interval, for a screen that has just opened.
///
/// Kept beside the provider because both answer the same question -- "is anybody there?" -- and split from it
/// because the provider's stream is about a list while this is about a moment.
Future<void> pingDiscovery(Ref ref) async {
  // The provider owns the socket; asking it for a value is what opens it. Nothing else to do here, and saying
  // so is better than an empty function nobody understands.
  await ref.read(discoveredDevicesProvider.future);
}
