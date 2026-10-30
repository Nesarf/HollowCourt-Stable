import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/chat_actions.dart';

/// **The action log: what she touched, and the two states a line can be in.**
///
/// The property worth testing is that a call which never came back is still visible. Every other log records
/// successes, and a log that only records successes cannot answer "did she try anything while I was out".
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-actions-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  ChatAction call(String tool, Map<String, Object?> arguments) => ChatAction(
        at: DateTime.utc(2026, 10, 30, 12),
        tool: tool,
        arguments: arguments,
      );

  test('**a call is written before its answer, and settled afterwards**', () async {
    final store = ChatActionStore(directory);
    final index = await store.start(call('read_cellar', <String, Object?>{}));

    var lines = await ChatActionStore(directory).read();
    expect(lines, hasLength(1));
    expect(lines.single.settled, isFalse, reason: 'an unfinished call is a fact, not a gap');
    expect(lines.single.summary, contains('未回执'));

    await store.settle(index, 'gin · 700 ml');
    lines = await ChatActionStore(directory).read();
    expect(lines.single.settled, isTrue);
    expect(lines.single.result, contains('700 ml'));
  });

  test('**the arguments survive, so the call can be reconstructed**', () async {
    final store = ChatActionStore(directory);
    await store.start(call('web_search', <String, Object?>{'query': '金酒 价格'}));
    final lines = await store.read();
    expect(lines.single.arguments['query'], '金酒 价格');
    expect(lines.single.summary, contains('金酒 价格'));
  });

  test('**a long answer is trimmed rather than stored whole**', () async {
    final store = ChatActionStore(directory);
    final index = await store.start(call('web_search', <String, Object?>{'query': 'x'}));
    await store.settle(index, 'y' * 2000);
    final lines = await store.read();
    expect(lines.single.result.length, lessThan(500));
    expect(lines.single.result, endsWith('…'));
  });

  test('**settling a line that is no longer there does nothing, and does not throw**', () async {
    // The log can be trimmed between a call and its answer; a missing line must not fail the turn that asked.
    final store = ChatActionStore(directory);
    await store.start(call('read_cellar', <String, Object?>{}));
    await store.settle(99, 'late');
    final lines = await store.read();
    expect(lines, hasLength(1));
    expect(lines.single.settled, isFalse);
  });

  test('**only the newest lines are kept**', () async {
    final store = ChatActionStore(directory, maxEntries: 3);
    for (var i = 0; i < 5; i++) {
      await store.start(call('read_cellar', <String, Object?>{'i': i}));
    }
    final lines = await ChatActionStore(directory, maxEntries: 3).read();
    expect(lines, hasLength(3));
    expect(lines.first.arguments['i'], 2);
    expect(lines.last.arguments['i'], 4);
  });

  test('**a broken file reads as no log, and clearing leaves none**', () async {
    await File('${directory.path}${Platform.pathSeparator}chat-actions.json').writeAsString('{oops');
    expect(await ChatActionStore(directory).read(), isEmpty);

    final store = ChatActionStore(directory);
    await store.start(call('read_cellar', <String, Object?>{}));
    await store.clear();
    expect(await store.read(), isEmpty);
  });
}
