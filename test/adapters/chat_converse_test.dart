import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/adapters/chat_client.dart';

/// **The half of the client the screen actually runs.**
///
/// `chat_client_test.dart` covers `stream`, which the tests use and the conversation does not. What runs when a
/// reader says something is `converse`, and until this file existed it had no test at all: not the tool calls that
/// arrive as fragments of JSON, not the `reasoning_content` that has to come back with them, and not the round limit
/// that stops a model from asking for tools forever.
void main() {
  const endpoint = ChatEndpoint(baseUrl: 'https://api.example.test/v1', model: 'm', apiKey: 'k');

  String chunk(Map<String, Object?> delta) =>
      'data: ${jsonEncode({'choices': [{'delta': delta}]})}';

  String text(String piece) => chunk({'content': piece});

  /// The shape a provider uses to stream one tool call: the name once, then the arguments in pieces.
  List<String> toolCallStream(String name, String arguments, {String id = 'call_1'}) {
    final pieces = <String>[];
    pieces.add(chunk({
      'tool_calls': [
        {
          'index': 0,
          'id': id,
          'function': {'name': name, 'arguments': ''},
        },
      ],
    }));
    // Slice the JSON three characters at a time: the point of the test is that a half-arrived object is never
    // decoded, and a single-piece delivery would not exercise that.
    for (var at = 0; at < arguments.length; at += 3) {
      final end = at + 3 > arguments.length ? arguments.length : at + 3;
      pieces.add(chunk({
        'tool_calls': [
          {
            'index': 0,
            'function': {'arguments': arguments.substring(at, end)},
          },
        ],
      }));
    }
    pieces.add('data: [DONE]');
    return pieces;
  }

  Future<String> collect(Stream<String> pieces) async {
    final buffer = StringBuffer();
    await for (final piece in pieces) {
      buffer.write(piece);
    }
    return buffer.toString();
  }

  group('trimHistory', () {
    ChatMessage user(int n) => ChatMessage.user('问 $n');
    ChatMessage her(int n) => ChatMessage.assistant('答 $n');

    test('a short transcript is left alone, system prompt included', () {
      final history = <ChatMessage>[
        const ChatMessage.system('她是伊丽莎白'),
        user(1), her(1), user(2), her(2),
      ];
      final kept = ChatClient.trimHistory(history);
      expect(kept, hasLength(5));
      expect(kept.first.role, ChatRole.system);
    });

    test('**only the newest exchanges are sent, and the model is told so**', () {
      final history = <ChatMessage>[
        const ChatMessage.system('她是伊丽莎白'),
        for (var n = 1; n <= 20; n++) ...<ChatMessage>[user(n), her(n)],
      ];
      final kept = ChatClient.trimHistory(history, keepTurns: 3);
      // One system prompt, one notice, then three whole exchanges.
      expect(kept, hasLength(1 + 1 + 6));
      expect(kept[0].text, '她是伊丽莎白');
      expect(kept[1].text, contains('更早'));
      expect(kept[2].text, '问 18');
      expect(kept.last.text, '答 20');
    });

    test('**an exchange is kept or dropped whole, never cut inside a tool round**', () {
      // A `tool_calls` message without its `tool` answers is a request DeepSeek refuses outright, so a cut through
      // the middle of one would turn a long conversation into a 400 rather than into a shorter one.
      final history = <ChatMessage>[
        const ChatMessage.system('p'),
        const ChatMessage.user('库存'),
        const ChatMessage.assistant(
          '',
          reasoning: '要先读',
          toolCalls: <ChatToolCall>[ChatToolCall(id: 'c1', name: 'read_cellar', arguments: <String, Object?>{})],
        ),
        const ChatMessage.tool('gin · 700 ml', toolCallId: 'c1'),
        const ChatMessage.assistant('有琴酒'),
        const ChatMessage.user('再来'),
        const ChatMessage.assistant('好'),
      ];
      final kept = ChatClient.trimHistory(history, keepTurns: 1);
      // The last exchange only: the user turn and the reply. The tool round above it went with its exchange.
      expect(kept.map((m) => m.role), <ChatRole>[ChatRole.system, ChatRole.system, ChatRole.user, ChatRole.assistant]);
      expect(kept.last.text, '好');
      expect(kept.any((m) => m.role == ChatRole.tool), isFalse);
    });

    test('a history of nothing but a prompt is just the prompt', () {
      expect(ChatClient.trimHistory(<ChatMessage>[const ChatMessage.system('p')]), hasLength(1));
      expect(ChatClient.trimHistory(const <ChatMessage>[]), isEmpty);
    });
  });

  group('mimeOf', () {
    test('**the four signatures, because the picker returns whatever the gallery holds**', () {
      expect(ChatClient.mimeOf(Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0])), 'image/jpeg');
      expect(
        ChatClient.mimeOf(Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])),
        'image/png',
      );
      expect(
        ChatClient.mimeOf(Uint8List.fromList(<int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61])),
        'image/gif',
      );
      expect(
        ChatClient.mimeOf(Uint8List.fromList(<int>[
          0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50,
        ])),
        'image/webp',
      );
    });

    test('**HEIC is named rather than passed off as JPEG**', () {
      // `ftypheic` at offset 4, brand at 8 -- what a modern Android camera roll produces.
      final heic = Uint8List.fromList(<int>[
        0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63,
      ]);
      expect(ChatClient.mimeOf(heic), 'image/heic');
      final avif = Uint8List.fromList(<int>[
        0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66,
      ]);
      expect(ChatClient.mimeOf(avif), 'image/avif');
    });

    test('an unknown blob falls back to the one every provider accepts', () {
      expect(ChatClient.mimeOf(Uint8List.fromList(<int>[1, 2, 3])), 'image/jpeg');
    });
  });

  group('converse', () {
    test('**a tool call arriving in fragments becomes one call, then an answer**', () async {
      final arguments = '{"query":"茅台 2024 价格"}';
      var transports = 0;
      final client = ChatClient(transport: (endpoint, body) {
        transports++;
        if (transports == 1) {
          // First round: the model asks for a tool and says nothing else.
          return Stream<String>.fromIterable(toolCallStream('web_search', arguments));
        }
        return Stream<String>.fromIterable(<String>[text('查到了，'), text('不便宜。'), 'data: [DONE]']);
      });

      ChatToolCall? ran;
      final answer = await collect(client.converse(
        endpoint,
        <ChatMessage>[const ChatMessage.user('茅台多少钱')],
        tools: <Map<String, Object?>>[
          <String, Object?>{'type': 'function'},
        ],
        runTool: (call) async {
          ran = call;
          return '约 2800 元';
        },
      ));

      expect(answer, '查到了，不便宜。');
      expect(ran, isNotNull);
      expect(ran!.name, 'web_search');
      // The whole point: three-character fragments reassembled into one object.
      expect(ran!.arguments['query'], '茅台 2024 价格');
      expect(transports, 2);
    });

    test('**the reasoning is carried back, because DeepSeek answers 400 without it**', () async {
      final bodies = <Map<String, Object?>>[];
      var transports = 0;
      final client = ChatClient(transport: (endpoint, body) {
        bodies.add(body);
        transports++;
        if (transports == 1) {
          return Stream<String>.fromIterable(<String>[
            chunk({'reasoning_content': '先查一下'}),
            ...toolCallStream('read_cellar', '{}'),
          ]);
        }
        return Stream<String>.fromIterable(<String>[text('有'), '琴酒。', 'data: [DONE]']);
      });

      await collect(client.converse(
        endpoint,
        <ChatMessage>[const ChatMessage.user('有什么')],
        tools: <Map<String, Object?>>[
          <String, Object?>{'type': 'function'},
        ],
        runTool: (call) async => 'gin · 700 ml',
      ));

      final second = bodies[1]['messages']! as List<Object?>;
      final assistant = second.firstWhere(
        (message) => (message! as Map<String, Object?>)['role'] == 'assistant',
      )! as Map<String, Object?>;
      expect(assistant['reasoning_content'], '先查一下');
      expect(assistant['tool_calls'], isA<List<Object?>>());
      // And the tool answer is addressed to the call that asked for it.
      final tool = second.firstWhere(
        (message) => (message! as Map<String, Object?>)['role'] == 'tool',
      )! as Map<String, Object?>;
      expect(tool['tool_call_id'], 'call_1');
      expect(tool['content'], 'gin · 700 ml');
    });

    test('**a model that only ever asks for tools is stopped, and told apart from a refusal**', () async {
      final client = ChatClient(transport: (endpoint, body) {
        return Stream<String>.fromIterable(toolCallStream('read_cellar', '{}'));
      });
      await expectLater(
        collect(client.converse(
          endpoint,
          <ChatMessage>[const ChatMessage.user('循环')],
          tools: <Map<String, Object?>>[
            <String, Object?>{'type': 'function'},
          ],
          runTool: (call) async => 'gin · 700 ml',
          maxRounds: 3,
        )),
        throwsA(isA<ChatFailure>()
            .having((e) => e.trouble, 'trouble', ChatTrouble.toolLoop)
            .having((e) => e.detail, 'detail', contains('tools'))),
      );
    });

    test('an error inside a 200 is still an error, on this path too', () async {
      final client = ChatClient(transport: (endpoint, body) {
        return Stream<String>.fromIterable(<String>[
          'data: ${jsonEncode({'error': {'message': 'quota exhausted'}})}',
        ]);
      });
      await expectLater(
        collect(client.converse(endpoint, <ChatMessage>[const ChatMessage.user('hi')])),
        throwsA(isA<ChatFailure>().having((e) => e.trouble, 'trouble', ChatTrouble.refused)),
      );
    });

    test('**no key means nothing is sent, before any round begins**', () async {
      var called = false;
      final client = ChatClient(transport: (endpoint, body) {
        called = true;
        return const Stream<String>.empty();
      });
      await expectLater(
        collect(client.converse(
          const ChatEndpoint(baseUrl: 'https://api.example.test/v1', model: 'm', apiKey: ''),
          <ChatMessage>[const ChatMessage.user('hi')],
        )),
        throwsA(isA<ChatFailure>().having((e) => e.trouble, 'trouble', ChatTrouble.notConfigured)),
      );
      expect(called, isFalse);
    });
  });
}
