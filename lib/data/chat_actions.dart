import 'dart:convert';
import 'dart:io';

/// **What she did, kept where the reader can look.**
///
/// The conversation transcript keeps what was said; this keeps what was *done*. They are separate files because they
/// answer different questions: "what did we talk about" and "what did she touch". A reader who wants to know whether
/// the bottle count changed during a conversation should not have to read the conversation to find out.
///
/// The tool call is recorded before the result and again after it, so an action that hung or crashed still leaves a
/// line saying it was attempted -- which is the case that matters, because the successful ones are visible in the
/// ledger anyway.
class ChatAction {
  const ChatAction({
    required this.at,
    required this.tool,
    required this.arguments,
    this.result = '',
    this.settled = false,
  });

  factory ChatAction.fromJson(Map<String, Object?> json) => ChatAction(
        at: DateTime.tryParse('${json['at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        tool: '${json['tool'] ?? ''}',
        arguments: json['arguments'] is Map
            ? Map<String, Object?>.from(json['arguments']! as Map)
            : const <String, Object?>{},
        result: '${json['result'] ?? ''}',
        settled: json['settled'] == true,
      );

  final DateTime at;
  final String tool;

  /// What it was asked with. The query, the sku, the volume -- enough to reconstruct the call without the prompt.
  final Map<String, Object?> arguments;

  /// What came back, trimmed. Empty while the call is still running.
  final String result;

  /// False while in flight. A line that stays false is a call that never came back, which is a fact worth being able
  /// to see rather than a gap in the record.
  final bool settled;

  ChatAction settle(String result) => ChatAction(
        at: at,
        tool: tool,
        arguments: arguments,
        result: result.length > 400 ? '${result.substring(0, 400)}…' : result,
        settled: true,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'at': at.toIso8601String(),
        'tool': tool,
        'arguments': arguments,
        'result': result,
        'settled': settled,
      };

  /// One line for a screen: the tool, its most telling argument, and whether it finished.
  String get summary {
    final argument = arguments['query'] ?? arguments['sku'] ?? arguments['millilitres'] ?? '';
    return '$tool${argument.toString().isEmpty ? '' : ' · $argument'}${settled ? '' : ' · (未回执)'}';
  }
}

/// **The action log, bounded like the transcript and for the same reason.**
///
/// Five hundred lines is roughly a month of ordinary use. Older lines fall off the front rather than being archived:
/// an action log that grows without limit is a file that takes longer to read every week, and nobody asked for a
/// second history.
class ChatActionStore {
  ChatActionStore(this.directory, {this.maxEntries = 500});

  final Directory directory;
  final int maxEntries;

  File get _file => File('${directory.path}${Platform.pathSeparator}chat-actions.json');

  Future<List<ChatAction>> read() async {
    final file = _file;
    if (!await file.exists()) return const <ChatAction>[];
    final Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } on FormatException {
      return const <ChatAction>[];
    }
    if (decoded is! List) return const <ChatAction>[];
    return <ChatAction>[
      for (final item in decoded)
        if (item is Map<String, Object?>) ChatAction.fromJson(item),
    ];
  }

  /// Adds one line, and answers with its index so the caller can settle it later.
  Future<int> start(ChatAction action) async {
    // `read` answers a fresh growable list; a `const <ChatAction>[]` from the empty-file branch is not.
    final lines = List<ChatAction>.of(await read());
    lines.add(action);
    await _write(lines);
    return lines.length - 1;
  }

  /// Fills in the result of a line already written. **Silently does nothing if the index is gone** -- the log may
  /// have been trimmed between the call and its answer, and a missing line is not a reason to fail the turn.
  Future<void> settle(int index, String result) async {
    final lines = List<ChatAction>.of(await read());
    if (index < 0 || index >= lines.length) return;
    lines[index] = lines[index].settle(result);
    await _write(lines);
  }

  Future<void> clear() async {
    final file = _file;
    if (await file.exists()) await file.delete();
  }

  Future<void> _write(List<ChatAction> lines) async {
    await directory.create(recursive: true);
    final kept = lines.length <= maxEntries ? lines : lines.sublist(lines.length - maxEntries);
    await _file.writeAsString(
      jsonEncode(<Object?>[for (final line in kept) line.toJson()]),
      flush: true,
    );
  }
}
