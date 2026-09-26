import 'dart:convert';
import 'dart:io';

import '../../domain/sync/device_identity.dart';

/// This device's key and the devices it has decided to recognise, in one file.
///
/// **One file for both, because they are one fact.** An identity with nothing remembered is a device
/// nobody can recognise; a remembered list with no identity is a device that cannot prove it is
/// itself. They are written together and read together, and a split would be two chances for the two
/// halves to disagree about which device this is.
///
/// **A file, and it holds a private key.** Everything else this application stores is either the
/// reader's own notes or a cache it could rebuild; this is the only secret at rest, and it is the
/// same trust boundary as the cellar log beside it -- readable by anyone who can read this
/// application's support directory. Recorded rather than implied, because "it is only a local file"
/// is how a key ends up in a backup that goes somewhere else.
final class SyncIdentityStore {
  const SyncIdentityStore(this.file);

  final File file;

  /// What is stored, or null when there is nothing usable to read.
  ///
  /// **A file that cannot be read is a new device, not an error.** Absent, empty, truncated by a kill
  /// during a write, or hand-edited into something else: none of those is a condition worth refusing
  /// to open over. The cost is a new identity, which a peer will refuse once and then learn again --
  /// annoying, and better than a program that will not start because a key file is corrupt.
  Future<StoredSyncIdentity?> read() async {
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return null;

      final seedText = decoded['seed'];
      if (seedText is! String || seedText.isEmpty) return null;
      final seed = base64.decode(seedText);

      final trusted = <TrustedDevice>[];
      final raw = decoded['trusted'];
      if (raw is List) {
        for (final entry in raw) {
          final device = TrustedDevice.fromJson(entry);
          // A malformed entry is skipped rather than failing the file: losing the whole list because
          // one record is wrong would forget every device somebody had paired.
          if (device != null) trusted.add(device);
        }
      }

      return StoredSyncIdentity(
        identity: await DeviceIdentity.fromSeed(seed),
        trusted: trusted,
      );
    } catch (_) {
      // Deliberately silent: a key file that cannot be read means a new identity, which is a state
      // this program handles rather than a reason to refuse to start.
      return null;
    }
  }

  Future<void> write(StoredSyncIdentity stored) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(<String, Object?>{
          'seed': base64.encode(await stored.identity.seed()),
          'trusted': [for (final device in stored.trusted) device.toJson()],
        }),
      );
    } catch (_) {
      // Deliberately silent, and unlike the read this one has a consequence worth naming: a write
      // that failed means the identity is regenerated next launch and every peer refuses this device
      // once. There is nothing to tell the reader at this point -- the sync they just ran already
      // succeeded -- so it is recorded here instead.
    }
  }
}

/// What the store holds: one identity, and the devices it has learned.
final class StoredSyncIdentity {
  const StoredSyncIdentity({required this.identity, required this.trusted});

  final DeviceIdentity identity;
  final List<TrustedDevice> trusted;

  /// The record for [publicKey], or null when this device has not been learned.
  TrustedDevice? known(String publicKey) {
    for (final device in trusted) {
      if (device.publicKey == publicKey) return device;
    }
    return null;
  }

  /// Adds [device], or updates the one already known under the same key.
  ///
  /// **Keyed on the key and not on the name.** Two devices can honestly be called `laptop`, and a
  /// name that moved between keys would transfer a trust decision to a device nobody had met.
  StoredSyncIdentity remembering(TrustedDevice device) => StoredSyncIdentity(
    identity: identity,
    trusted: [
      for (final known in trusted)
        if (known.publicKey != device.publicKey) known,
      device,
    ],
  );
}
