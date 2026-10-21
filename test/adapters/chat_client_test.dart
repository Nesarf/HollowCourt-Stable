import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/adapters/chat_client.dart';
import 'package:hollow_court/adapters/elizabeth_prompt.dart';

/// **The conversation client, tested against what providers actually send.**
///
/// The transport is injected, so no test here touches the network and none of them changes its mind when a provider
/// revises a model. What is exercised is the part that is easy to get wrong: server-sent events arriving in pieces, an
/// error delivered inside a 200, a stream that ends with `[DONE]`, a stream that ends with nothing, and the two wire
/// shapes -- text alone, and text with a photograph.
void main() {
  const endpoint = ChatEndpoint(baseUrl: 'https://api.example.test/v1', model: 'm', apiKey: 'k');

  ChatClient answering(List<String> lines) => ChatClient(transport: (endpoint, body) => Stream<String>.fromIterable(lines));

  String chunk(String piece) => 'data: ${jsonEncode({'choices': [{'delta': {'content': piece}}]})}';

  Future<String> collect(Stream<String> pieces) async {
    final buffer = StringBuffer();
    await for (final piece in pieces) {
      buffer.write(piece);
    }
    return buffer.toString();
  }

  test('**the pieces of a reply add up to the reply**', () async {
    final client = answering(<String>[
      chunk('这瓶'),
      chunk('是二锅头'),
      '',
      ': keep-alive',
      'data: [DONE]',
    ]);
    expect(await collect(client.stream(endpoint, [const ChatMessage.user('这是什么')])), '这瓶是二锅头');
  });

  test('**an error inside a 200 is an error**', () async {
    // The shape that would otherwise be swallowed: a provider answers 200, then sends the failure as a chunk.
    final client = answering(<String>[
      'data: ${jsonEncode({'error': {'message': 'quota exhausted'}})}',
    ]);
    await expectLater(
      collect(client.stream(endpoint, [const ChatMessage.user('hi')])),
      throwsA(isA<ChatFailure>().having((e) => e.trouble, 'trouble', ChatTrouble.refused)),
    );
  });

  test('**an empty stream is a failure, not a silent success**', () async {
    // Silence is the one answer a screen cannot explain, so it is turned into one that it can.
    final client = answering(<String>['data: [DONE]']);
    await expectLater(
      collect(client.stream(endpoint, [const ChatMessage.user('hi')])),
      throwsA(isA<ChatFailure>().having((e) => e.trouble, 'trouble', ChatTrouble.unreachable)),
    );
  });

  test('**no key means nothing is sent**', () async {
    var called = false;
    final client = ChatClient(transport: (endpoint, body) {
      called = true;
      return const Stream<String>.empty();
    });
    await expectLater(
      collect(client.stream(
        const ChatEndpoint(baseUrl: 'https://api.example.test/v1', model: 'm', apiKey: '  '),
        [const ChatMessage.user('hi')],
      )),
      throwsA(isA<ChatFailure>().having((e) => e.trouble, 'trouble', ChatTrouble.notConfigured)),
    );
    expect(called, isFalse, reason: 'a request with no key is a request that should not exist');
  });

  test('**the body carries the model, the stream flag and the history**', () async {
    Map<String, Object?>? seen;
    final client = ChatClient(transport: (endpoint, body) {
      seen = body;
      return Stream<String>.fromIterable(<String>[chunk('ok')]);
    });
    await collect(client.stream(endpoint, [
      const ChatMessage.system('be her'),
      const ChatMessage.user('这是什么'),
      const ChatMessage.assistant('先让我看看'),
      const ChatMessage.user('再看'),
    ]));
    expect(seen!['model'], 'm');
    expect(seen!['stream'], isTrue);
    final messages = seen!['messages']! as List<Object?>;
    expect(messages, hasLength(4));
    expect((messages[0]! as Map<String, Object?>)['role'], 'system');
    // Text alone stays a plain string: a content list of one is the shape older providers reject.
    expect((messages[1]! as Map<String, Object?>)['content'], '这是什么');
  });

  test('**a photograph becomes a data URL, beside the text**', () async {
    Map<String, Object?>? seen;
    final client = ChatClient(transport: (endpoint, body) {
      seen = body;
      return Stream<String>.fromIterable(<String>[chunk('看到了')]);
    });
    await collect(client.stream(endpoint, [
      ChatMessage.user('这是什么酒', image: Uint8List.fromList(<int>[1, 2, 3, 4])),
    ]));
    final messages = seen!['messages']! as List<Object?>;
    final content = (messages.single as Map<String, Object?>)['content']! as List<Object?>;
    expect(content, hasLength(2));
    expect((content[0]! as Map<String, Object?>)['type'], 'text');
    final image = (content[1]! as Map<String, Object?>)['image_url']! as Map<String, Object?>;
    expect(image['url'], startsWith('data:image/jpeg;base64,'));
    expect(image['url'], endsWith(base64Encode(<int>[1, 2, 3, 4])));
  });

  test('**the endpoint is a base plus one path, and the host is readable for the disclosure**', () {
    expect(endpoint.completions.toString(), 'https://api.example.test/v1/chat/completions');
    expect(endpoint.host, 'api.example.test');
    // A trailing slash is not a different address.
    const trailing = ChatEndpoint(baseUrl: 'https://api.example.test/v1/', model: 'm', apiKey: 'k');
    expect(trailing.completions.toString(), 'https://api.example.test/v1/chat/completions');
  });

  test('**the prompt says the things the model would otherwise get wrong**', () {
    // A guard on the prompt itself: these are the rules that turn a chatbot into a voice that does not invent a
    // distillery and does not flatter. Losing one in an edit would be invisible until a reader believed a label.
    expect(elizabethSystemPrompt, contains('本小姐'));
    expect(elizabethSystemPrompt, contains('编造'));
    expect(elizabethSystemPrompt, contains('看不清'));
    expect(elizabethSystemPrompt, contains('库存'));
    // And it must be the person on the owner's sheet: the 45th head of d'Armanac, who prefers 大小姐 to 家主.
    expect(elizabethSystemPrompt, contains('阿曼纳克'));
    expect(elizabethSystemPrompt, contains('大小姐'));
    // It must NOT be the other person: a draft that had put 晴光 in this slot was corrected on 2026-10-22.
    expect(elizabethSystemPrompt, isNot(contains('珐丽安')));
    expect(elizabethSystemPrompt, isNot(contains('骑士团')));
  });
}
