
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/registry.dart';
import 'adapters_providers.dart';
import 'chat_providers.dart';
import 'chat_page.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'theme.dart';

/// **The door, and what it says before it opens.**
///
/// The conversation was built as three fields in the settings and nothing else, which was a seam that had not declared
/// itself -- the one thing section 11's disclosure exists to prevent. It is a registered adapter now, with the same
/// card, the same switch and the same vocabulary as the barcode, and the card says the two things that matter:
///
/// * the address is not written here, because **the reader types it** -- so the card says "the address you entered"
///   rather than naming a host it cannot know;
/// * **anything she reads from the cellar is sent.** `read_cellar` puts the shelves into the conversation, so
///   `sendsAnythingAboutTheCellar` is true for this seam and false for the barcode, and that difference is the whole
///   reason the flag exists.
///
/// The switch is the consent. A reader who has not turned it on cannot start a conversation, whatever is in the key
/// field -- `chat_page.dart` asks this registry before it sends anything.
class ChatSeamCard extends ConsumerWidget {
  const ChatSeamCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(adapterRegistryProvider);
    final adapter = registry.adapterFor(AdapterKind.chatModel);
    if (adapter == null) return const SizedBox.shrink();
    final enabled = registry.isEnabled(AdapterKind.chatModel);
    final settings = ref.watch(chatSettingsProvider).value;
    final host = settings == null || settings.baseUrl.trim().isEmpty
        ? ref.copy(Copy.chatDisclosureNoAddress)
        : Uri.tryParse(settings.baseUrl)?.host ?? settings.baseUrl;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: HollowPalette.ink.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: DualCopyText(Copy.chatTitle, style: HollowType.body)),
              Switch(
                key: const ValueKey('chat-seam-switch'),
                value: enabled,
                onChanged: (on) =>
                    ref.read(adapterRegistryProvider.notifier).setEnabled(AdapterKind.chatModel, on),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // **What leaves, in the adapter's own vocabulary.** `hosts` is empty by construction here, so the sentence
          // is assembled from the address the reader entered rather than from a constant that would be a guess.
          Text(
            '${ref.copy(Copy.chatDisclosureSends)} $host · ${ref.copy(Copy.chatDisclosurePayload)}',
            style: HollowType.caption,
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                key: const ValueKey('chat-open'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(builder: (_) => const ChatPage()),
                ),
                child: DualCopyText(Copy.chatOpen, style: HollowType.body),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


