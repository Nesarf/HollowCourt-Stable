import 'dart:convert';
import 'dart:io';

import '../../domain/sync/names.dart';

/// Where this device's two names are kept between launches.
///
/// **A separate file from the identity, and the reason is what each one is.** The identity file holds a
/// key and a list of devices met before; losing it costs a re-pairing. This holds two strings a person
/// typed, and losing it costs nothing but the typing -- so it is deliberately the more forgiving of the
/// two, and neither of them can break the other by being unreadable.
///
/// The pattern is `display.json`'s: absent, empty, truncated by a kill during a write, or hand-edited
/// into something else are all "a first run", and the one thing this must not do is throw.
final class SyncNamesStore {
  const SyncNamesStore(this.file);

  final File file;

  /// What was stored, or null when there is nothing usable to read.
  Future<SyncNames?> read({required String fallbackDeviceName}) async {
    try {
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, Object?>) return null;
      return SyncNames.fromJson(decoded, fallbackDeviceName: fallbackDeviceName);
    } on Object {
      // Silent on purpose, and the same argument as the display settings: a name is a label, and an
      // unreadable label must never be the reason an application does not open.
      return null;
    }
  }

  Future<void> write(SyncNames names) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(names.toJson()));
  }
}
