import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// **Where the conversation is sent.** An OpenAI-compatible endpoint, because that is one shape most providers speak:
/// the address, a model name, and a key. Nothing about this class knows which company answers.
class ChatEndpoint {
  const ChatEndpoint({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  /// The base, without `/chat/completions` -- e.g. `https://api.deepseek.com/v1`. Kept as the base so a provider that
  /// appends a different path is a change here rather than at every call site.
  final String baseUrl;
  final String model;
  final String apiKey;

  Uri get completions => Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}/chat/completions');

  /// The host that will see the conversation, for the disclosure card.
  String get host => completions.host;
}

enum ChatRole { system, user, assistant, tool }

/// One turn, with an optional picture attached to it.
///
/// **The picture is here because a barcode that cannot be found is the reason this exists.** A label can be
/// photographed; the digits on it cannot always be looked up. An image is carried as raw bytes and encoded at the
/// edge, so nothing in the domain has to know what a data URL is.
class ChatMessage {
  const ChatMessage(
    this.role,
    this.text, {
    this.image,
    this.reasoning = '',
    this.toolCalls = const <ChatToolCall>[],
    this.toolCallId,
  });

  const ChatMessage.system(this.text)
      : role = ChatRole.system,
        image = null,
        reasoning = '',
        toolCalls = const <ChatToolCall>[],
        toolCallId = null;
  const ChatMessage.user(this.text, {this.image})
      : role = ChatRole.user,
        reasoning = '',
        toolCalls = const <ChatToolCall>[],
        toolCallId = null;
  const ChatMessage.assistant(this.text, {this.reasoning = '', this.toolCalls = const <ChatToolCall>[]})
      : role = ChatRole.assistant,
        image = null,
        toolCallId = null;

  /// The answer from one tool, addressed to the call that asked for it.
  const ChatMessage.tool(this.text, {required String this.toolCallId})
      : role = ChatRole.tool,
        image = null,
        reasoning = '',
        toolCalls = const <ChatToolCall>[];

  final ChatRole role;
  final String text;
  final Uint8List? image;

  /// **The model's own reasoning, which must be sent back when a tool was involved.** DeepSeek answers 400 if a
  /// conversation that carried `tools` comes back without it, and the stream delivers it as `reasoning_content`
  /// beside `content`. Empty for a plain turn, and ignored by providers that do not use it.
  final String reasoning;

  /// What this assistant turn asked the application to run, for the turn to be replayed.
  final List<ChatToolCall> toolCalls;

  /// Which call this tool result answers. Required on a [ChatRole.tool] message.
  final String? toolCallId;

  bool get hasImage => image != null && image!.isNotEmpty;
}

/// **What went wrong, in the five ways it goes wrong.**
///
/// Told apart because the screen says something different for each, and because "no key" and "the key is wrong" send
/// the reader to two different places: the first to the settings, the second to the provider's console.
enum ChatTrouble {
  /// No key or no address configured: nothing was sent.
  notConfigured,
  /// The provider refused the key.
  unauthorised,
  /// Rate limit, quota, or the provider's own 4xx.
  refused,
  /// No network, a timeout, a broken stream, or a 5xx.
  unreachable,
  /// **She kept asking for tools and never answered.** Its own case rather than `refused`, because it is not the
  /// provider's judgement about the key or the quota -- it is this application stopping a loop it will not pay for,
  /// and the reader reading "refused" would go and check a key that is working perfectly.
  toolLoop,
}

class ChatFailure implements Exception {
  const ChatFailure(this.trouble, this.detail);
  final ChatTrouble trouble;
  final String detail;

  @override
  String toString() => 'ChatFailure(${trouble.name}: $detail)';
}

/// One thing the model asked the application to run.
class ChatToolCall {
  const ChatToolCall({required this.id, required this.name, required this.arguments});

  final String id;
  final String name;
  final Map<String, Object?> arguments;

  @override
  String toString() => '$name(${arguments['query'] ?? arguments})';
}

/// Sends a conversation and answers with the pieces of the reply as they arrive.
typedef ChatTransport = Stream<String> Function(ChatEndpoint endpoint, Map<String, Object?> body);

/// **The conversation, spoken over HTTP.**
///
/// The transport is injectable so the tests can feed it a recording of what a provider actually sends -- which is the
/// only part of this file worth testing, because the rest is a `POST` and a loop.
class ChatClient {
  const ChatClient({ChatTransport? transport}) : _transport = transport; // ignore: prefer_initializing_formals

  final ChatTransport? _transport;

  /// **The part of a transcript the next request carries.**
  ///
  /// A conversation is persisted and grows without limit, and every turn re-sends all of it: the prompt, every reply,
  /// and whatever the tools read. `read_recipes` alone can return thirty recipes with every line of every one, and
  /// that answer then rides along on every request after it. The cost is not the size of one reply; it is the size of
  /// the archive multiplied by the number of turns, and it is paid again on each one.
  ///
  /// **What is trimmed is the request, not the conversation.** The screen keeps every turn and the store keeps every
  /// turn; this only decides what the model is asked to read. The cut is made at a `user` message and never inside a
  /// tool round, because a `tool_calls` message whose `tool` answers were dropped is a request the provider rejects
  /// outright -- so exchanges are kept or dropped whole.
  static List<ChatMessage> trimHistory(List<ChatMessage> history, {int keepTurns = 8}) {
    final system = <ChatMessage>[for (final message in history) if (message.role == ChatRole.system) message];
    final rest = <ChatMessage>[for (final message in history) if (message.role != ChatRole.system) message];
    if (rest.isEmpty) return system;

    var turns = 0;
    var cut = 0;
    for (var i = rest.length - 1; i >= 0; i--) {
      if (rest[i].role == ChatRole.user) {
        turns++;
        if (turns == keepTurns) {
          cut = i;
          break;
        }
      }
    }
    final kept = rest.sublist(cut);
    if (cut == 0) return <ChatMessage>[...system, ...kept];

    // **The model is told the transcript is partial.** A reader who resumes a stored conversation would otherwise be
    // answered by someone who cannot remember the beginning and does not say so -- which reads as a memory problem
    // rather than as a decision made here.
    return <ChatMessage>[
      ...system,
      const ChatMessage.system('（更早的对话这一段不再发送，只保留最近的部分。需要旧内容时，请读者再说一次。）'),
      ...kept,
    ];
  }

  /// The reply as it arrives, piece by piece. **A stream rather than a future**, because a reply that appears as it is
  /// written is the difference between a conversation and a wait; the collector gets the whole text by joining.
  Stream<String> stream(ChatEndpoint endpoint, List<ChatMessage> history) {
    if (endpoint.apiKey.trim().isEmpty) {
      return Stream<String>.error(const ChatFailure(ChatTrouble.notConfigured, 'no key'));
    }
    final body = <String, Object?>{
      'model': endpoint.model,
      'stream': true,
      'messages': [for (final message in history) _wire(message)],
    };
    final raw = (_transport ?? _httpTransport)(endpoint, body);
    return _pieces(raw);
  }

  /// **What the bytes actually are.** The library picker hands back whatever the gallery holds -- PNG, WebP, and
  /// HEIC or AVIF on newer Android -- while the camera writes JPEG. Declaring all of it `image/jpeg` was a claim
  /// about the file that the file could contradict, and a provider that trusts the label over the bytes is the one
  /// that breaks. Four signatures cover everything this application can produce.
  static String mimeOf(Uint8List bytes) {
    bool at(int index, List<int> signature) {
      if (bytes.length < index + signature.length) return false;
      for (var i = 0; i < signature.length; i++) {
        if (bytes[index + i] != signature[i]) return false;
      }
      return true;
    }

    if (at(0, <int>[0x89, 0x50, 0x4E, 0x47])) return 'image/png';
    if (at(0, <int>[0xFF, 0xD8, 0xFF])) return 'image/jpeg';
    if (at(0, <int>[0x47, 0x49, 0x46, 0x38])) return 'image/gif';
    if (at(0, <int>[0x52, 0x49, 0x46, 0x46]) && at(8, <int>[0x57, 0x45, 0x42, 0x50])) return 'image/webp';
    if (at(4, <int>[0x66, 0x74, 0x79, 0x70]) && bytes.length >= 12) {
      // ISO base media: the brand at offset 8 says which member of the family this is.
      final brand = String.fromCharCodes(bytes.sublist(8, 12));
      if (brand.startsWith('hei') || brand.startsWith('mif') || brand.startsWith('msf')) return 'image/heic';
      if (brand.startsWith('avi')) return 'image/avif';
    }
    // A fourth answer is worse than a plausible guess here: every provider accepts JPEG, and an unlabelled blob it
    // cannot type is the failure that arrives as a 400 with no explanation.
    return 'image/jpeg';
  }

  /// The wire shape. An image becomes a `data:` URL inside a content list; text alone stays a plain string, because
  /// that is what every provider accepts and a list-of-one is the shape that trips the older ones.
  static Object _wire(ChatMessage message) {
    final role = switch (message.role) {
      ChatRole.system => 'system',
      ChatRole.user => 'user',
      ChatRole.assistant => 'assistant',
      ChatRole.tool => 'tool',
    };
    if (message.role == ChatRole.tool) {
      return <String, Object?>{
        'role': 'tool',
        'tool_call_id': message.toolCallId,
        'content': message.text,
      };
    }
    if (message.role == ChatRole.assistant && message.toolCalls.isNotEmpty) {
      return <String, Object?>{
        'role': 'assistant',
        'content': message.text,
        'reasoning_content': message.reasoning,
        'tool_calls': <Object?>[
          for (final call in message.toolCalls)
            <String, Object?>{
              'id': call.id,
              'type': 'function',
              'function': <String, Object?>{
                'name': call.name,
                'arguments': jsonEncode(call.arguments),
              },
            },
        ],
      };
    }
    if (!message.hasImage) return <String, Object?>{'role': role, 'content': message.text};
    return <String, Object?>{
      'role': role,
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': message.text},
        <String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{
            'url': 'data:${mimeOf(message.image!)};base64,${base64Encode(message.image!)}',
          },
        },
      ],
    };
  }

  /// **Server-sent events, read as they stream.**
  ///
  /// A provider sends `data: {...}` lines, one token (or a few) each, and ends with `data: [DONE]`. Anything that is
  /// not one of those lines -- a comment, a keep-alive, an empty line -- is skipped rather than reported: the stream
  /// is not a document, and treating it as one is how a decoder starts apologising for the protocol.
  static Stream<String> _pieces(Stream<String> lines) async* {
    final buffer = StringBuffer();
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload == '[DONE]') break;
      if (payload.isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<String, Object?>) continue;
      // **An error can arrive inside a 200**, which is the failure this loop would otherwise swallow: the provider
      // answers 200 and then sends `{"error": {...}}` as a chunk.
      final error = decoded['error'];
      if (error is Map<String, Object?>) {
        throw ChatFailure(ChatTrouble.refused, '${error['message'] ?? error}');
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) continue;
      final first = choices.first;
      if (first is! Map<String, Object?>) continue;
      final delta = first['delta'];
      if (delta is! Map<String, Object?>) continue;
      final piece = delta['content'];
      if (piece is String && piece.isNotEmpty) buffer.write(piece);
      if (piece is String) yield piece;
    }
    if (buffer.isEmpty) {
      // Nothing arrived and nothing failed: a provider that answered 200 with an empty stream. Rare, and silence is
      // the one answer the screen cannot explain, so it is made into one it can.
      throw const ChatFailure(ChatTrouble.unreachable, 'empty stream');
    }
  }

  /// **A whole conversation, including the part where the model asks to look something up.**
  ///
  /// One round per model turn. A turn that ends in `tool_calls` is not an answer: the calls are run, their results are
  /// appended, and the model is asked again -- at most [maxRounds] times, because a model that keeps asking for tools
  /// is a model to stop rather than to pay for.
  ///
  /// **`reasoning_content` is carried through.** DeepSeek's own documentation is explicit: a request that carries
  /// `tools` and then comes back without the reasoning of the earlier turns is answered with 400. So each assistant
  /// turn keeps what the model thought, even though the reader never sees it.
  ///
  /// [onThought] receives the reasoning as it streams, for a screen that wants to show that something is happening
  /// before the first word of the answer exists.
  Stream<String> converse(
    ChatEndpoint endpoint,
    List<ChatMessage> history, {
    List<Map<String, Object?>> tools = const <Map<String, Object?>>[],
    Future<String> Function(ChatToolCall call)? runTool,
    void Function(String piece)? onThought,
    int maxRounds = 4,
  }) async* {
    if (endpoint.apiKey.trim().isEmpty) {
      throw const ChatFailure(ChatTrouble.notConfigured, 'no key');
    }
    final messages = List<ChatMessage>.of(history);
    for (var round = 0; round < maxRounds; round++) {
      final body = <String, Object?>{
        'model': endpoint.model,
        'stream': true,
        'messages': [for (final message in messages) _wire(message)],
        if (tools.isNotEmpty) ...<String, Object?>{
          'tools': tools,
          // Thinking is on by default for this model, and asked for explicitly so that a provider which defaults it
          // off is not silently a worse assistant.
          'thinking': <String, Object?>{'type': 'enabled'},
          'reasoning_effort': 'high',
        },
      };
      final raw = (_transport ?? _httpTransport)(endpoint, body);

      final text = StringBuffer();
      final reasoning = StringBuffer();
      final calls = <int, _PartialCall>{};
      var pieces = 0;

      await for (final line in raw) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload == '[DONE]') break;
        if (payload.isEmpty) continue;
        Object? decoded;
        try {
          decoded = jsonDecode(payload);
        } on FormatException {
          continue;
        }
        if (decoded is! Map<String, Object?>) continue;
        final error = decoded['error'];
        if (error is Map<String, Object?>) {
          throw ChatFailure(ChatTrouble.refused, '${error['message'] ?? error}');
        }
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final first = choices.first;
        if (first is! Map<String, Object?>) continue;
        final delta = first['delta'];
        if (delta is! Map<String, Object?>) continue;
        final thought = delta['reasoning_content'];
        if (thought is String && thought.isNotEmpty) {
          reasoning.write(thought);
          onThought?.call(thought);
        }
        final piece = delta['content'];
        if (piece is String && piece.isNotEmpty) {
          text.write(piece);
          pieces++;
          yield piece;
        }
        final deltas = delta['tool_calls'];
        if (deltas is List) {
          for (final item in deltas) {
            if (item is! Map<String, Object?>) continue;
            final index = (item['index'] as num?)?.toInt() ?? 0;
            final partial = calls.putIfAbsent(index, _PartialCall.new);
            partial.absorb(item);
          }
        }
      }

      if (calls.isEmpty) {
        if (pieces == 0) {
          throw const ChatFailure(ChatTrouble.unreachable, 'empty stream');
        }
        return;
      }

      // **A turn that asked for tools is remembered and answered, not shown.** What the reader sees is the sentence
      // that comes after the fact was found, which is the only part worth their attention.
      final wanted = <ChatToolCall>[
        for (final partial in calls.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
          partial.value.finish(),
      ];
      messages.add(ChatMessage.assistant(text.toString(), reasoning: reasoning.toString(), toolCalls: wanted));
      for (final call in wanted) {
        final answer = runTool == null ? 'No tool is available.' : await runTool(call);
        messages.add(ChatMessage.tool(answer, toolCallId: call.id));
      }
    }
    throw const ChatFailure(ChatTrouble.toolLoop, 'the model kept asking for tools');
  }

  /// The real transport: one POST, and the body read as lines.
  static Stream<String> _httpTransport(ChatEndpoint endpoint, Map<String, Object?> body) async* {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(endpoint.completions);
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.userAgentHeader, 'HollowCourt/1.0 (github.com/Nesarf/HollowCourt-Stable)');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${endpoint.apiKey}');
      request.write(jsonEncode(body));
      final response = await request.close();
      if (response.statusCode == 401 || response.statusCode == 403) {
        await response.drain<void>();
        throw const ChatFailure(ChatTrouble.unauthorised, 'the provider refused the key');
      }
      if (response.statusCode >= 400) {
        final text = await response.transform(utf8.decoder).join();
        throw ChatFailure(ChatTrouble.refused, 'HTTP ${response.statusCode}: ${text.trim()}');
      }
      // **An idle timeout, because `connectionTimeout` covers only the handshake.** A provider that accepts the
      // connection and then says nothing held the screen on its spinner for as long as the application ran. Sixty
      // seconds between events, not sixty seconds in total: keep-alive lines reset it, so a slow answer survives and
      // a dead one does not.
      yield* response.transform(utf8.decoder).transform(const LineSplitter()).timeout(
        const Duration(seconds: 60),
        onTimeout: (EventSink<String> sink) {
          sink.addError(const ChatFailure(ChatTrouble.unreachable, 'the reply stopped arriving'));
          sink.close();
        },
      );
    } on SocketException catch (error) {
      throw ChatFailure(ChatTrouble.unreachable, error.message);
    } on IOException catch (error) {
      // **`SocketException` is not the only way a connection fails.** `HandshakeException` (TLS refused, which is what
      // a proxy or an intercepting certificate produces) and `HttpException` (the server closed mid-stream) are
      // siblings under `IOException`, and catching only the first let the other two escape as themselves -- straight
      // past the screen's `on ChatFailure`, leaving it busy for the rest of the run with no way back but a restart.
      throw ChatFailure(ChatTrouble.unreachable, '$error');
    } finally {
      client.close();
    }
  }
}

/// **One tool call being streamed in pieces.** The `arguments` of a call arrive as fragments of a JSON string, one
/// chunk at a time, so they are appended and parsed once at the end rather than decoded per chunk -- decoding a
/// half-arrived object would throw on every call.
class _PartialCall {
  String? id;
  String name = '';
  final StringBuffer args = StringBuffer();
  Map<String, Object?> _parsed = const <String, Object?>{};

  void absorb(Map<String, Object?> item) {
    id ??= item['id'] as String?;
    final function = item['function'];
    if (function is Map<String, Object?>) {
      final called = function['name'];
      if (called is String && called.isNotEmpty) name = called;
      final arguments = function['arguments'];
      if (arguments is String) args.write(arguments);
    }
  }

  ChatToolCall finish() {
    if (args.isNotEmpty) {
      try {
        final decoded = jsonDecode(args.toString());
        if (decoded is Map<String, Object?>) _parsed = decoded;
      } on FormatException {
        // A provider that sent something unparseable gets an empty argument map, and the tool runner decides what to
        // say about that -- better than throwing inside a stream where the reader sees nothing.
      }
    }
    return ChatToolCall(id: id ?? '', name: name, arguments: _parsed);
  }
}
