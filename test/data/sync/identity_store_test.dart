import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/sync/identity_store.dart';
import 'package:hollow_court/domain/sync/device_identity.dart';

/// The one file that holds a private key, and the difference between *absent* and *broken*.
///
/// **[The defect these tests are for, found by review on 2026-10-01.]** `SyncIdentityStore.read` answered `null`
/// for every failure -- absent, empty, truncated by a kill during a write, or hand-edited into something else --
/// on the reasoning that a corrupt key file is not worth refusing to open over. The reasoning is sound and the
/// conclusion was wrong, because *"a new identity"* is not a harmless outcome:
///
/// * The reader is given no explanation. Peers start refusing this device, and the two states a reader can observe
///   -- the key file is unreadable, and this is a new device -- look identical from outside.
/// * **The corrupt file is then overwritten**, because the provider writes a fresh identity immediately. Whatever
///   could have been recovered by looking at it is gone on the next launch.
///
/// So absent is `null` and broken throws, and these tests hold that line.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('identity_store'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File file() => File('${dir.path}${Platform.pathSeparator}sync-identity.json');

  Future<StoredSyncIdentity> sample() async => StoredSyncIdentity(
    identity: await DeviceIdentity.generate(),
    trusted: const [],
  );

  group('absent and broken are different answers', () {
    test('a file that is not there is null, which is the ordinary first launch', () async {
      // This is the case the old behaviour was written for, and it is still right: nothing exists yet, so there is
      // nothing to report and nothing to lose.
      expect(await SyncIdentityStore(file()).read(), isNull);
    });

    test('**a file that exists and cannot be parsed throws instead of becoming a new device**', () async {
      final f = file();
      await f.writeAsString('{ this is not json');

      await expectLater(
        SyncIdentityStore(f).read(),
        throwsA(isA<IdentityUnreadable>()),
        reason: 'reporting null here means the provider writes a fresh identity over the top, and the reader is '
            'never told that the device their peers knew has been replaced',
      );
    });

    test('**an empty file is broken, not absent**', () async {
      // It exists, which means this device had an identity; a zero-byte file is a write that did not finish, and
      // that is exactly the state worth refusing to paper over.
      final f = file();
      await f.writeAsString('');
      await expectLater(SyncIdentityStore(f).read(), throwsA(isA<IdentityUnreadable>()));
    });

    test('a file with no seed throws rather than reading as a new device', () async {
      final f = file();
      await f.writeAsString('{"trusted":[]}');
      await expectLater(SyncIdentityStore(f).read(), throwsA(isA<IdentityUnreadable>()));
    });

    test('a seed that is not base64 throws', () async {
      final f = file();
      await f.writeAsString('{"seed":"not base64 at all!!","trusted":[]}');
      await expectLater(SyncIdentityStore(f).read(), throwsA(isA<IdentityUnreadable>()));
    });

    test('the error names the file, so somebody can go and look at it', () async {
      final f = file();
      await f.writeAsString('broken');
      try {
        await SyncIdentityStore(f).read();
        fail('expected IdentityUnreadable');
      } on IdentityUnreadable catch (error) {
        expect(error.path, f.path);
        expect(error.cause, isNotNull, reason: 'a message that is only a shrug is not worth printing');
      }
    });
  });

  group('what it writes', () {
    test('a written identity reads back as the same device', () async {
      final f = file();
      final stored = await sample();
      await SyncIdentityStore(f).write(stored);

      final back = await SyncIdentityStore(f).read();
      expect(back, isNotNull);
      expect(back!.identity.publicKey, stored.identity.publicKey);
      expect(back.identity.fingerprint, stored.identity.fingerprint);
    });

    test('**the write leaves no half-written file behind to be read**', () async {
      // The rename is the point: `writeAsString` truncates and then writes, so a kill in between leaves a file
      // that exists, is not empty, and is not valid JSON -- the exact state `read` now reports instead of hiding.
      final f = file();
      await SyncIdentityStore(f).write(await sample());

      expect(f.existsSync(), isTrue);
      expect(
        File('${f.path}.writing').existsSync(),
        isFalse,
        reason: 'the temporary file must be renamed away, not left beside the real one',
      );
      // And what is at the real path is complete, which is what the atomic rename guarantees.
      expect(await SyncIdentityStore(f).read(), isNotNull);
    });

    test('writing twice replaces rather than appends', () async {
      final f = file();
      final first = await sample();
      await SyncIdentityStore(f).write(first);
      final second = await sample();
      await SyncIdentityStore(f).write(second);

      final back = await SyncIdentityStore(f).read();
      expect(back!.identity.publicKey, second.identity.publicKey);
      expect(back.identity.publicKey, isNot(first.identity.publicKey));
    });
  });
}
