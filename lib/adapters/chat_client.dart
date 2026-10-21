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

enum ChatRole { system, user, assistant }

/// One turn, with an optional picture attached to it.
///
/// **The picture is here because a barcode that cannot be found is the reason this exists.** A label can be
/// photographed; the digits on it cannot always be looked up. An image is carried as raw bytes and encoded at the
/// edge, so nothing in the domain has to know what a data URL is.
class ChatMessage {
  const ChatMessage(this.role, this.text, {this.image});

  const ChatMessage.system(this.text)
      : role = ChatRole.system,
        image = null;
  const ChatMessage.user(this.text, {this.image})
      : role = ChatRole.user;
  const ChatMessage.assistant(this.text)
      : role = ChatRole.assistant,
        image = null;

  final ChatRole role;
  final String text;
  final Uint8List? image;

  bool get hasImage => image != null && image!.isNotEmpty;
}

/// **What went wrong, in the four ways it goes wrong.**
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
}

class ChatFailure implements Exception {
  const ChatFailure(this.trouble, this.detail);
  final ChatTrouble trouble;
  final String detail;

  @override
  String toString() => 'ChatFailure(${trouble.name}: $detail)';
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

  /// The wire shape. An image becomes a `data:` URL inside a content list; text alone stays a plain string, because
  /// that is what every provider accepts and a list-of-one is the shape that trips the older ones.
  static Object _wire(ChatMessage message) {
    final role = switch (message.role) {
      ChatRole.system => 'system',
      ChatRole.user => 'user',
      ChatRole.assistant => 'assistant',
    };
    if (!message.hasImage) return <String, Object?>{'role': role, 'content': message.text};
    return <String, Object?>{
      'role': role,
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': message.text},
        <String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{
            'url': 'data:image/jpeg;base64,${base64Encode(message.image!)}',
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
      yield* response.transform(utf8.decoder).transform(const LineSplitter());
    } on SocketException catch (error) {
      throw ChatFailure(ChatTrouble.unreachable, error.message);
    } finally {
      client.close();
    }
  }
}
