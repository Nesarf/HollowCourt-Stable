import 'dart:convert';
import 'dart:io';

import '../adapters/chat_client.dart';

/// **The conversation, kept between visits, and bounded.**
///
/// It was deliberately not stored in the first round, and the reason it is stored now is the reason it was not then:
/// a transcript is a record of something the reader said to a machine, and keeping it is a decision rather than a
/// default. The owner made that decision on 2026-10-22, so here it is, with three rules that follow from it:
///
/// 1. **On this machine only.** Nothing here is sent anywhere; the file sits beside the cellar and the key.
/// 2. **Bounded.** The last [maxEntries] turns, because an unbounded transcript is a file that grows forever and a
///    page that takes longer to open every week. What falls off the front is gone rather than archived -- keeping a
///    second ring of old conversations would be a feature nobody asked for and a second thing to explain.
/// 3. **Plain text, in the clear.** The reasoning and the tool calls are not stored: what the reader saw is what is
///    kept. Encrypting it was considered and rejected on the same grounds the key store explains -- a passphrase every
///    launch for a conversation is not a conversation, and a key sitting beside the file is not encryption.
class ChatHistoryStore {
  ChatHistoryStore(this.directory, {this.maxEntries = 200});

  final Directory directory;
  final int maxEntries;

  File get _file => File('${directory.path}${Platform.pathSeparator}chat-history.json');

  /// The stored turns, oldest first. An unreadable file reads as no history: a transcript is a convenience, and
  /// refusing to open the page because it was edited into nonsense would make it a liability.
  Future<List<ChatMessage>> read() async {
    final file = _file;
    if (!await file.exists()) return const <ChatMessage>[];
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException {
      return const <ChatMessage>[];
    }
    if (decoded is! List) return const <ChatMessage>[];
    final messages = <ChatMessage>[];
    for (final item in decoded) {
      if (item is! Map<String, Object?>) continue;
      final role = '${item['role'] ?? ''}';
      final text = '${item['text'] ?? ''}';
      if (text.isEmpty) continue;
      messages.add(switch (role) {
        'user' => ChatMessage.user(text),
        'assistant' => ChatMessage.assistant(text),
        _ => ChatMessage.system(text),
      });
    }
    return messages;
  }

  /// Replaces the file with what is on screen, trimming to the newest [maxEntries] turns.
  Future<void> write(List<ChatMessage> messages) async {
    await directory.create(recursive: true);
    final kept = messages.length <= maxEntries ? messages : messages.sublist(messages.length - maxEntries);
    final json = <Object?>[
      for (final message in kept)
        <String, Object?>{
          'role': switch (message.role) {
            ChatRole.user => 'user',
            ChatRole.assistant => 'assistant',
            ChatRole.system => 'system',
            ChatRole.tool => 'tool',
          },
          'text': message.text,
        },
    ];
    await _file.writeAsString(jsonEncode(json), flush: true);
  }

  /// Forgets everything, and says so by leaving no file rather than an empty array.
  Future<void> clear() async {
    final file = _file;
    if (await file.exists()) await file.delete();
  }
}
