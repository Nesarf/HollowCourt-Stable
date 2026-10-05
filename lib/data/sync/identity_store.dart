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

  /// What is stored, or **null when there is nothing yet**.
  ///
  /// **The distinction this function now makes, and why it did not before.** It used to answer null for every
  /// failure -- absent, empty, truncated by a kill during a write, or hand-edited into something else -- on the
  /// reasoning that a corrupt key file is not worth refusing to open over. **The reasoning is sound and the
  /// conclusion was wrong**, because "a new identity" is not a harmless outcome:
  ///
  /// * The reader gets no explanation. Peers begin refusing this device, and the two states a reader can see --
  ///   *the key file is unreadable* and *this is a new device* -- look identical from the outside.
  /// * **The corrupt file is then overwritten**, because `build` writes a fresh identity immediately. Whatever a
  ///   person could have recovered by looking at it is gone on the next launch.
  ///
  /// So: **absent is null and broken throws.** Absent is the ordinary first launch; broken is a condition worth
  /// saying out loud, and the provider above surfaces it rather than starting again quietly. An empty or
  /// unparseable file is broken, not absent -- it exists, which means this device had an identity.
  Future<StoredSyncIdentity?> read() async {
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      // **Everything from here on is a file that exists**, so every failure below is reported rather than
      // answered with `null` -- see the note on this method. An empty file is a write that did not finish, and a
      // missing seed is a file that was never an identity; both mean this device *had* one.
      if (text.trim().isEmpty) throw IdentityUnreadable(file.path, 'the file is empty');
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) {
        throw IdentityUnreadable(file.path, 'the file is not a JSON object');
      }

      final seedText = decoded['seed'];
      if (seedText is! String || seedText.isEmpty) {
        throw IdentityUnreadable(file.path, 'the file has no seed');
      }
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
    } on IdentityUnreadable {
      rethrow;
    } catch (error) {
      // **Anything else is a file that exists and cannot be used**, which is a different fact from a file that is
      // not there. Reported with the path so a reader can find it, and with the cause so the message is not a
      // shrug.
      throw IdentityUnreadable(file.path, error);
    }
  }

  /// Writes the identity **through a temporary file and a rename**, and lets a failure out.
  ///
  /// **The rename is what makes a half-written file impossible.** `writeAsString` truncates and then writes, so a
  /// process killed in between leaves a file that exists, is not empty, and is not valid JSON -- which is exactly
  /// the state `read` used to answer null to, and which the comment above now describes as worth reporting. A
  /// rename over the target is atomic on the filesystems this runs on, so the file is either the old one or the
  /// new one and never a fragment of either.
  ///
  /// **The error propagates**, where it used to be swallowed. A caller that cannot persist an identity has lost
  /// every pairing it makes from here on, and only the caller knows whether that is worth telling somebody about;
  /// a store that decides for it is a store that guarantees nobody is told.
  Future<void> write(StoredSyncIdentity stored) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.writing');
    await temporary.writeAsString(
      jsonEncode(<String, Object?>{
        'seed': base64.encode(await stored.identity.seed()),
        'trusted': [for (final device in stored.trusted) device.toJson()],
      }),
      flush: true,
    );
    // `rename` replaces on every platform this ships to, and `File.rename` is synchronous on the target's own
    // directory. A leftover `.writing` file from a kill is harmless: it is never read, and the next write
    // overwrites it.
    await temporary.rename(file.path);
  }
}

/// The identity file exists and cannot be used.
///
/// **Its own type rather than a generic exception**, because the caller has a real decision here -- whether to
/// report it or to carry on without sync -- and a caller cannot make that decision about an error it cannot name.
final class IdentityUnreadable implements Exception {
  const IdentityUnreadable(this.path, this.cause);

  final String path;
  final Object cause;

  @override
  String toString() => 'IdentityUnreadable($path): $cause';
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
