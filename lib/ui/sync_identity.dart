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

/// **Whether this device failed to write its own identity down**, and the message to show if so.
///
/// **The other half of the silence the store used to keep.** `_persist` is deliberately not awaited -- a screen
/// must be able to say a device was remembered without waiting on a file (see [SyncIdentityNotifier.remember]) --
/// and its failure used to be caught and dropped, so the sequence was: a sync succeeds, the device is remembered,
/// the write fails, and next launch this device is a stranger to everybody. Nothing anywhere said so, and the
/// reader's only clue was peers refusing them.
///
/// It is its own provider rather than a field on [StoredSyncIdentity] because it is not part of what is stored:
/// a value that carried its own write error would be a claim about the file kept inside the file.
final syncIdentityWriteFailureProvider =
    NotifierProvider<SyncIdentityWriteFailureNotifier, String?>(
  SyncIdentityWriteFailureNotifier.new,
);

class SyncIdentityWriteFailureNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void report(String message) => state = message;

  void clear() => state = null;
}

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
      // Cleared on success, because a warning that never goes away is a warning nobody reads.
      ref.read(syncIdentityWriteFailureProvider.notifier).clear();
    } catch (error) {
      // **Recorded rather than dropped.** This used to be an empty `on Object`, and the consequence is the one
      // worth naming: the sync that caused this write has already succeeded, so the reader is told everything
      // worked and finds out otherwise days later when a peer refuses them. The message says what is lost.
      // **The cause and not a sentence.** The words a reader sees come from `Copy.syncIdentityNotSaved`, so
      // that this message exists in every language the application speaks; what is kept here is the technical
      // detail, which is diagnostic and belongs beside the failure rather than translated.
      ref.read(syncIdentityWriteFailureProvider.notifier).report('$error');
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
