import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/sync/names_store.dart';
import '../domain/sync/names.dart';

/// Where the two names live.
final syncNamesFileProvider = FutureProvider<File>((Ref ref) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}names.json');
});

/// This device's names, and which of them it shows.
///
/// **A default that is honest about what the machine will not say.** `Platform.localHostname` is the
/// obvious source and is not reliably useful -- it answers `localhost` on Android, which would put every
/// phone into a peer's list under one name (see `SyncNames.defaultsFor`). The fallback names the platform
/// rather than pretending to know the machine, and the reader can type over it.
final syncNamesProvider = AsyncNotifierProvider<SyncNamesNotifier, SyncNames>(
  SyncNamesNotifier.new,
);

class SyncNamesNotifier extends AsyncNotifier<SyncNames> {
  @override
  Future<SyncNames> build() async {
    final fallback = SyncNames.defaultsFor(
      Platform.localHostname,
      isAndroid: Platform.isAndroid,
    ).deviceName;

    // **Read through `.value`, never awaited**, for the reason the sync section learned the hard way: a
    // provider that reads a *file* through a platform channel never completes in a widget test, and a
    // screen that awaits it is a screen that never draws.
    final file = ref.watch(syncNamesFileProvider).value;
    if (file == null) return SyncNames.defaultsFor(fallback, isAndroid: Platform.isAndroid);

    final stored = await SyncNamesStore(file).read(fallbackDeviceName: fallback);
    return stored ?? SyncNames(deviceName: fallback);
  }

  /// Remembers the file once it arrives, so a change made before the path resolved is not lost.
  Future<void> _persist(SyncNames names) async {
    state = AsyncData(names);
    final file = ref.read(syncNamesFileProvider).value;
    if (file == null) return;
    await SyncNamesStore(file).write(names);
  }

  Future<void> setDeviceName(String name) async {
    final current = state.value;
    if (current == null) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _persist(current.withDeviceName(trimmed));
  }

  /// **An empty cellar name is allowed, and is a real state**: it means "not named yet", and the
  /// presentation falls back to the device name rather than putting a blank row in somebody's list.
  Future<void> setCellarName(String name) async {
    final current = state.value;
    if (current == null) return;
    await _persist(current.withCellarName(name.trim()));
  }

  Future<void> setChoice(NameChoice choice) async {
    final current = state.value;
    if (current == null) return;
    await _persist(current.withChoice(choice));
  }
}
