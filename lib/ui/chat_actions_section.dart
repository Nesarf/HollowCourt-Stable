import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_actions.dart';
import 'chat_providers.dart';
import 'l10n/dual_copy_text.dart';
import 'theme.dart';

/// **What she did, in the settings where the other facts about this build live.**
///
/// The log has been written since 2026-10-22 and was invisible until now, which is the shape a record takes when it is
/// written for an auditor rather than for the person who was there. The reader who enabled the conversation is the
/// one entitled to see it, and this is the shortest path to that: a list, newest first, with the tool, what it was
/// asked, and whether it came back.
///
/// **Newest first, because the question is almost always "what just happened".** The file is oldest first -- appends
/// are cheap that way -- and the reversal happens here.
class ChatActionsSection extends ConsumerWidget {
  const ChatActionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(chatActionsProvider);
    return actions.when(
      loading: () => const SizedBox(height: 24),
      error: (error, stack) => const SizedBox(height: 24),
      data: (store) {
        return FutureBuilder<List<ChatAction>>(
          future: store.read(),
          builder: (context, snapshot) {
            final lines = snapshot.data ?? const <ChatAction>[];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 22),
                DualCopyText(Copy.chatActionsTitle, style: HollowType.title),
                const SizedBox(height: 6),
                DualCopyText(Copy.chatActionsNote, style: HollowType.caption),
                const SizedBox(height: 8),
                if (lines.isEmpty)
                  DualCopyText(Copy.chatActionsEmpty, style: HollowType.caption)
                else
                  for (final action in lines.reversed.take(20))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The time is the part that makes a log navigable: without it every line looks like now.
                          Text(
                            '${action.at.hour.toString().padLeft(2, '0')}:'
                            '${action.at.minute.toString().padLeft(2, '0')}',
                            style: HollowType.numeric.copyWith(color: HollowPalette.text.faint),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              action.summary,
                              style: HollowType.caption.copyWith(
                                color: action.settled ? HollowPalette.inkSoft : HollowPalette.rose,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                if (lines.length > 20)
                  DualCopyText(
                    Copy.chatActionsMore,
                    style: HollowType.caption.copyWith(color: HollowPalette.text.faint),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
