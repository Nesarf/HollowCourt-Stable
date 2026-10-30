import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/adapters/chat_client.dart';
import 'package:hollow_court/data/chat_history.dart';

/// **The transcript file: what survives, what does not, and what happens when it is broken.**
///
/// Three properties matter and each is a rule the class states: it keeps what the reader saw (not the reasoning and
/// not the tool calls), it keeps only the newest turns, and a file somebody edited into nonsense takes the page down
/// with it or it does not -- and the answer has to be that it does not.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-history-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('**the reader and the reply come back in order**', () async {
    final store = ChatHistoryStore(directory);
    await store.write(<ChatMessage>[
      const ChatMessage.user('今天金酒的行情怎么样'),
      const ChatMessage.assistant('这个本小姐得去查。'),
    ]);

    final read = await ChatHistoryStore(directory).read();
    expect(read, hasLength(2));
    expect(read.first.role, ChatRole.user);
    expect(read.first.text, '今天金酒的行情怎么样');
    expect(read.last.role, ChatRole.assistant);
  });

  test('**reasoning and tool calls are not kept**', () async {
    // What the reader saw is what is kept. A transcript that also stored the model's thinking would be a different
    // file with a different promise, and nobody asked for it.
    final store = ChatHistoryStore(directory);
    await store.write(<ChatMessage>[
      const ChatMessage.assistant('查到了。', reasoning: '我应该先看行情', toolCalls: <ChatToolCall>[
        ChatToolCall(id: 'c1', name: 'web_search', arguments: <String, Object?>{'query': 'gin price'}),
      ]),
    ]);
    final text = await File('${directory.path}${Platform.pathSeparator}chat-history.json').readAsString();
    expect(text, isNot(contains('我应该先看行情')));
    expect(text, isNot(contains('web_search')));
    expect(text, contains('查到了。'));
  });

  test('**only the newest turns are kept**', () async {
    final store = ChatHistoryStore(directory, maxEntries: 3);
    await store.write(<ChatMessage>[
      for (var i = 0; i < 6; i++) ChatMessage.user('第 $i 句'),
    ]);
    final read = await ChatHistoryStore(directory, maxEntries: 3).read();
    expect(read, hasLength(3));
    expect(read.first.text, '第 3 句', reason: 'the oldest three fell off the front');
    expect(read.last.text, '第 5 句');
  });

  test('**a file edited into nonsense reads as no history**', () async {
    await File('${directory.path}${Platform.pathSeparator}chat-history.json').writeAsString('{{ not json');
    expect(await ChatHistoryStore(directory).read(), isEmpty);
    // And the page still opens, which is the property that matters.
  });

  test('**clearing leaves no file at all**', () async {
    final store = ChatHistoryStore(directory);
    await store.write(<ChatMessage>[const ChatMessage.user('hi')]);
    await store.clear();
    expect(await File('${directory.path}${Platform.pathSeparator}chat-history.json').exists(), isFalse);
    expect(await store.read(), isEmpty);
  });

  test('**nothing written yet is not an error**', () async {
    expect(await ChatHistoryStore(directory).read(), isEmpty);
  });

  test('**what is written is readable JSON with the roles spelled as words**', () async {
    final store = ChatHistoryStore(directory);
    await store.write(<ChatMessage>[
      const ChatMessage.user('a'),
      const ChatMessage.assistant('b'),
    ]);
    final decoded = jsonDecode(await File('${directory.path}${Platform.pathSeparator}chat-history.json').readAsString());
    expect(decoded, isA<List<Object?>>());
    expect((decoded as List<Object?>).first, <String, Object?>{'role': 'user', 'text': 'a'});
  });
}
