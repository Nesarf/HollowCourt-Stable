import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/chat_settings.dart';

/// **The settings file, and an honest account of what its lock is worth.**
///
/// The key is encrypted, and the master key sits in the same directory -- so the encryption stops a reader who opens
/// `chat.json` (or copies a backup off the device) from reading a credential by accident, and it stops nothing else.
/// That is written in the class and tested here, because a test that claimed more would be the start of somebody
/// trusting it with more.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat-settings-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('**what is written comes back, including the key**', () async {
    final store = ChatKeyStore(directory);
    await store.write(const ChatSettings(
      baseUrl: 'https://api.example.test/v1',
      model: 'some-model',
      apiKey: 'sk-test-0123456789',
    ));

    final read = await ChatKeyStore(directory).read();
    expect(read.baseUrl, 'https://api.example.test/v1');
    expect(read.model, 'some-model');
    expect(read.apiKey, 'sk-test-0123456789');
    expect(read.isConfigured, isTrue);
  });

  test('**the key is not in the file in clear**', () async {
    final store = ChatKeyStore(directory);
    await store.write(const ChatSettings(
      baseUrl: 'https://api.example.test/v1',
      model: 'some-model',
      apiKey: 'sk-test-0123456789',
    ));

    final text = await File('${directory.path}${Platform.pathSeparator}chat.json').readAsString();
    expect(text, isNot(contains('sk-test-0123456789')),
        reason: 'the whole point of the sealed field is that this does not appear');
    // The address and the model do appear, on purpose: they are not secrets, and a file nobody can read by eye is a
    // file nobody can repair.
    expect(text, contains('https://api.example.test/v1'));
  });

  test('**nothing written yet is not an error**', () async {
    final read = await ChatKeyStore(directory).read();
    expect(read.isConfigured, isFalse);
    expect(read.apiKey, isEmpty);
  });

  test('**a file somebody edited into nonsense reads as empty rather than throwing**', () async {
    await File('${directory.path}${Platform.pathSeparator}chat.json').writeAsString('{ not json');
    final read = await ChatKeyStore(directory).read();
    expect(read.isConfigured, isFalse);
  });

  test('**a master key that was replaced leaves the key unreadable, and the form still opens**', () async {
    final store = ChatKeyStore(directory);
    await store.write(const ChatSettings(
      baseUrl: 'https://api.example.test/v1',
      model: 'some-model',
      apiKey: 'sk-test-0123456789',
    ));
    // What a factory reset of the application directory looks like from the settings file's point of view: the
    // encrypted key survives, the master does not.
    await File('${directory.path}${Platform.pathSeparator}chat.master').writeAsBytes(List<int>.filled(32, 7));

    final read = await ChatKeyStore(directory).read();
    expect(read.baseUrl, 'https://api.example.test/v1');
    expect(read.model, 'some-model');
    expect(read.apiKey, isEmpty, reason: 'the reader types it again; that is the recovery');
    expect(read.isConfigured, isFalse);
  });

  test('**an empty key writes no sealed field at all**', () async {
    final store = ChatKeyStore(directory);
    await store.write(const ChatSettings(baseUrl: 'https://api.example.test/v1', model: 'm'));
    final text = await File('${directory.path}${Platform.pathSeparator}chat.json').readAsString();
    expect(text, isNot(contains('"key"')));
  });
}
