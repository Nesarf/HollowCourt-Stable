import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/folder_styles.dart';

/// The override layer's storage, which is the part that can lose a reader's words.
///
/// A folder style is the only place a reader's own naming of their library lives, so the two ways it can go
/// wrong both matter: a file that cannot be read must not take the library with it, and an empty style must not
/// be written out as if it were a real one (which would silently pin a folder to the derived defaults, making a
/// later change to the derivation invisible).
void main() {
  late Directory temp;
  late File file;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('folder-styles-test');
    file = File('${temp.path}${Platform.pathSeparator}folder_styles.json');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('a style survives a round trip, and an empty one is not written at all', () async {
    final store = FolderStyleStore(file);
    await store.write({
      'iba/The Unforgettables': const FolderStyle(name: '经典', note: 'IBA 的招牌', order: 10),
      'iba/New Era': const FolderStyle(), // nothing changed about this one
    });

    final read = await store.read();
    expect(read.keys, ['iba/The Unforgettables']);
    expect(read['iba/The Unforgettables']!.name, '经典');
    expect(read['iba/The Unforgettables']!.note, 'IBA 的招牌');
    expect(read['iba/The Unforgettables']!.order, 10);
    expect(read['iba/The Unforgettables']!.accent, isNull);
  });

  test('a reader who has never renamed anything has no file, and that is not an error', () async {
    final store = FolderStyleStore(file);
    expect(await store.read(), isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('**a damaged file is empty rather than fatal**', () async {
    // The same rule the display settings and the cellar follow. A reader whose settings file lost a brace must
    // still see their library; the alternative is an application that will not open because of a stray comma.
    file.writeAsStringSync('{ "iba/New Era": { "name": "X" ');
    expect(await FolderStyleStore(file).read(), isEmpty);

    file.writeAsStringSync('["not", "an", "object"]');
    expect(await FolderStyleStore(file).read(), isEmpty);
  });

  test('a store with no file at all is silent, which is what a test relies on', () async {
    const store = FolderStyleStore(null);
    expect(await store.read(), isEmpty);
    await store.write({'x/y': const FolderStyle(name: 'ignored')});
  });
}
