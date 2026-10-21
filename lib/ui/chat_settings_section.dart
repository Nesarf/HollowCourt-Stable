import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_settings.dart';
import 'chat_providers.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'theme.dart';

/// **Where the key, the address and the model are entered.** Last on the settings page, under the same heading as the
/// rest of the outside world.
///
/// The sentence under the three fields says what is sealed and what is not, and it is the sentence that has to be
/// true: the key is encrypted, the address and the model are not, and a reader who thinks otherwise would be trusting
/// the wrong half.
class ChatSettingsSection extends ConsumerStatefulWidget {
  const ChatSettingsSection({super.key});

  @override
  ConsumerState<ChatSettingsSection> createState() => _ChatSettingsSectionState();
}

class _ChatSettingsSectionState extends ConsumerState<ChatSettingsSection> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _key = TextEditingController();
  bool _loaded = false;
  bool _saved = false;

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  /// Fills the fields once, from the stored settings. **Once**, because a rebuild that re-filled them would undo
  /// whatever the reader was in the middle of typing.
  void _fill(ChatSettings settings) {
    if (_loaded) return;
    _loaded = true;
    _baseUrl.text = settings.baseUrl;
    _model.text = settings.model;
    _key.text = settings.apiKey;
  }

  Future<void> _save() async {
    await ref.read(chatSettingsProvider.notifier).save(ChatSettings(
          baseUrl: _baseUrl.text.trim(),
          model: _model.text.trim(),
          apiKey: _key.text.trim(),
        ));
    if (mounted) {
      setState(() => _saved = true);
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) setState(() => _saved = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(chatSettingsProvider);
    return settings.when(
      loading: () => const SizedBox(height: 24),
      error: (error, stack) => const SizedBox(height: 24),
      data: (value) {
        _fill(value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 22),
            DualCopyText(Copy.chatSettingsTitle, style: HollowType.title),
            const SizedBox(height: 6),
            DualCopyText(Copy.chatSettingsNote, style: HollowType.caption),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('chat-base-url'),
              controller: _baseUrl,
              style: HollowType.body,
              decoration: InputDecoration(
                labelText: ref.copy(Copy.chatBaseUrl),
                hintText: 'https://api.deepseek.com/v1',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('chat-model'),
              controller: _model,
              style: HollowType.body,
              decoration: InputDecoration(
                labelText: ref.copy(Copy.chatModel),
                hintText: 'deepseek-chat',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('chat-api-key'),
              controller: _key,
              style: HollowType.body,
              obscureText: true,
              decoration: InputDecoration(labelText: ref.copy(Copy.chatApiKey)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton(
                  key: const ValueKey('chat-save'),
                  onPressed: _save,
                  child: DualCopyText(Copy.chatSave, style: HollowType.body),
                ),
                const SizedBox(width: 12),
                if (_saved)
                  DualCopyText(Copy.chatSaved, style: HollowType.caption.copyWith(color: HollowPalette.gold)),
              ],
            ),
          ],
        );
      },
    );
  }
}
