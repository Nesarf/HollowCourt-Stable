import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/sync/identity_store.dart';
import '../domain/sync/device_identity.dart';

/// Where this device's key and its remembered peers live.
///
/// **Beside the cellar, in the application's support directory.** Not in the log: a private key is
/// not an event, it is not synced, and it must never travel to another device -- which is exactly
/// what putting it in the log would do.
final syncIdentityFileProvider = FutureProvider<File>((Ref ref) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}sync-identity.json');
});

/// This device's identity, created on first use and loaded after that.
///
/// **Created lazily and persisted immediately**, because the alternative is a device that is a
/// different device on every launch: a peer would refuse it every time, and the refusal would look
/// like a bug in the pairing code rather than like a key that was never saved.
final syncIdentityProvider =
    AsyncNotifierProvider<SyncIdentityNotifier, StoredSyncIdentity>(
  SyncIdentityNotifier.new,
);

class SyncIdentityNotifier extends AsyncNotifier<StoredSyncIdentity> {
  @override
  Future<StoredSyncIdentity> build() async {
    final file = await ref.watch(syncIdentityFileProvider.future);
    final store = SyncIdentityStore(file);
    final stored = await store.read();
    if (stored != null) return stored;

    // First launch with this feature: a new key, written before anything can ask for it.
    final fresh = StoredSyncIdentity(
      identity: await DeviceIdentity.generate(),
      trusted: const [],
    );
    await store.write(fresh);
    return fresh;
  }

  /// Adds [device] to what this device remembers, or updates what it knew about it.
  Future<void> remember(TrustedDevice device) async {
    final current = state.value;
    if (current == null) return;
    final next = current.remembering(device);
    state = AsyncData(next);
    // **Written after the state changes, and not awaited.** The screen has to be able to say the
    // device was remembered without waiting for a file: a write that goes through a platform channel
    // can be slow, and one that never completes would leave a sync that already succeeded looking
    // like it had not. The write is what makes it survive a restart, not what makes it true now.
    unawaited(_persist(next));
  }

  Future<void> _persist(StoredSyncIdentity value) async {
    try {
      final file = await ref.read(syncIdentityFileProvider.future);
      await SyncIdentityStore(file).write(value);
    } on Object {
      // A store that cannot be written costs the reader this decision next launch, and nothing
      // today. There is no screen to tell at this point.
    }
  }

  /// Forgets a device. **The only way a trust decision is ever undone**, and it exists because a
  /// decision a person cannot withdraw is not a decision they made.
  Future<void> forget(String publicKey) async {
    final current = state.value;
    if (current == null) return;
    final next = StoredSyncIdentity(
      identity: current.identity,
      trusted: [
        for (final device in current.trusted)
          if (device.publicKey != publicKey) device,
      ],
    );
    state = AsyncData(next);
    unawaited(_persist(next));
  }
}
