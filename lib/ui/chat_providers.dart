import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/chat_settings.dart';

/// Where the conversation settings live: beside the cellar, never inside the build.
final chatStoreProvider = FutureProvider<ChatKeyStore>((Ref ref) async {
  final directory = await getApplicationSupportDirectory();
  return ChatKeyStore(directory);
});

/// **The address, the model and the key, as one value.**
///
/// An `AsyncNotifier` because reading the file is a file read: the form shows its three fields greyed for a frame
/// rather than empty, which is the difference between "not configured" and "not loaded yet" -- two states that look
/// identical on screen and mean opposite things.
final chatSettingsProvider = AsyncNotifierProvider<ChatSettingsNotifier, ChatSettings>(ChatSettingsNotifier.new);

class ChatSettingsNotifier extends AsyncNotifier<ChatSettings> {
  @override
  Future<ChatSettings> build() async {
    final store = await ref.watch(chatStoreProvider.future);
    return store.read();
  }

  /// Writes, then reports the state that was written. **Not re-read from disk**: the value just handed over is the
  /// value, and a second read would race with nothing and fail for no reason.
  Future<void> save(ChatSettings settings) async {
    final store = await ref.read(chatStoreProvider.future);
    await store.write(settings);
    state = AsyncData(settings);
  }
}
