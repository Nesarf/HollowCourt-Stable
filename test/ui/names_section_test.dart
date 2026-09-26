import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/data/sync/names_store.dart';
import 'package:hollow_court/domain/sync/names.dart';
import 'package:hollow_court/ui/names_section.dart';
import 'package:hollow_court/ui/sync_names.dart';
import 'package:hollow_court/ui/theme.dart';

/// The names a device goes by, and the screen where the owner sets them.
///
/// The store half is about not throwing on a file that cannot be read; the screen half is about the one
/// state that would otherwise be silent -- **the cellar name is chosen before the cellar has one.**
void main() {
  late Directory home;

  setUp(() => home = Directory.systemTemp.createTempSync('hollow-names'));
  tearDown(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  File file() => File('${home.path}${Platform.pathSeparator}names.json');

  group('the names are a setting, and a setting never stops the application opening', () {
    test('a round trip through the file', () async {
      final store = SyncNamesStore(file());
      await store.write(
        const SyncNames(
          deviceName: 'NesarfDX',
          cellarName: '试验酒窖',
          shows: NameChoice.cellar,
        ),
      );

      final read = await store.read(fallbackDeviceName: 'fallback');
      expect(read!.deviceName, 'NesarfDX');
      expect(read.cellarName, '试验酒窖');
      expect(read.shows, NameChoice.cellar);
    });

    test('**an unreadable file is a first run, not an error**', () async {
      // Absent, empty, truncated by a kill during a write, or hand-edited into something else. A name is
      // a label, and an unreadable label must never be the reason an application does not open.
      final store = SyncNamesStore(file());
      expect(await store.read(fallbackDeviceName: 'NesarfDX'), isNull);

      await file().writeAsString('');
      expect(await store.read(fallbackDeviceName: 'NesarfDX'), isNull);

      await file().writeAsString('{"deviceName": "NesarfDX"');
      expect(await store.read(fallbackDeviceName: 'NesarfDX'), isNull);

      await file().writeAsString('[1,2,3]');
      expect(await store.read(fallbackDeviceName: 'NesarfDX'), isNull);

      // And a file written by a version that knew fewer fields keeps what it does have.
      await file().writeAsString('{"cellarName":"试验酒窖"}');
      final partial = await store.read(fallbackDeviceName: 'NesarfDX');
      expect(partial!.deviceName, 'NesarfDX', reason: 'the fallback fills the missing one');
      expect(partial.cellarName, '试验酒窖');
    });
  });

  group('the settings screen says which name goes out', () {
    Widget wrap(SyncNames names) => ProviderScope(
      overrides: [
        // **The notifier itself is replaced, not a provider invented beside it.** The real one reads a
        // file through a platform channel that never answers in a widget test, so a section left on it
        // would sit on a spinner forever -- and the first version of this file did exactly that, by
        // overriding a provider the screen never reads, which is a seam that only looks like a seam.
        syncNamesProvider.overrideWith(() => _FixedNames(names)),
      ],
      child: MaterialApp(
        theme: HollowTheme.build(),
        home: const Scaffold(body: SingleChildScrollView(child: NamesSection())),
      ),
    );

    testWidgets('both names are shown, with the one that is presented marked', (tester) async {
      await tester.pumpWidget(
        wrap(const SyncNames(deviceName: 'NesarfDX', cellarName: '试验酒窖')),
      );
      // The section reads an `AsyncNotifier`: the first frame is the spinner, and the value arrives on the
      // next. A test that stops at `pumpWidget` is testing the spinner.
      await tester.pump();

      expect(find.text('NesarfDX'), findsWidgets);
      expect(find.text('试验酒窖'), findsWidgets);
      // The device name is the default presentation, so that is what 对方看到的 says.
      expect(find.text(Copy.namesShownAs.primary.text), findsOneWidget);
      expect(find.text(Copy.namesUnnamedCellar.primary.text), findsNothing);
    });

    testWidgets('choosing the cellar name shows it as what goes out', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SyncNames(
            deviceName: 'NesarfDX',
            cellarName: '试验酒窖',
            shows: NameChoice.cellar,
          ),
        ),
      );
      await tester.pump();
      final shown = find.text('试验酒窖');
      expect(shown, findsWidgets);
    });

    testWidgets('**and it says so when the cellar has no name yet**', (tester) async {
      // The state that would otherwise be silent: the choice is a two-option control and the name is a
      // text field nobody has filled in. The device name still goes out -- and the reader is told, rather
      // than left to work out from two controls why their chosen name is not the one being shown.
      await tester.pumpWidget(
        wrap(const SyncNames(deviceName: 'NesarfDX', shows: NameChoice.cellar)),
      );
      await tester.pump();
      expect(find.text(Copy.namesUnnamedCellar.primary.text), findsOneWidget);
    });
  });
}

/// A notifier that answers a fixed value instead of reading the names file.
class _FixedNames extends SyncNamesNotifier {
  _FixedNames(this._initial);

  final SyncNames _initial;

  @override
  Future<SyncNames> build() async => _initial;
}
