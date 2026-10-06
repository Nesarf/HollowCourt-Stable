import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/events/court_pack.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/pack_editor.dart';
import 'package:hollow_court/ui/theme.dart';

/// Naming a folder -- `docs/proposal-recipes-and-packs.md` section 1's last requirement.
///
/// **What this proves and what it does not**, the same split `collection_editor_test` records: it uses a recorder
/// rather than a real `EventLog`, because a real file open does not complete under the fake clock a widget test runs
/// in. So it proves the sheet maps what a reader typed onto a `CourtPack` and refuses what it should; it does not
/// prove a pack survives a restart, which belongs to `PackBook.of` and is tested on real events.
class _FixedLocale extends LocaleSettingsNotifier {
  @override
  LocaleSettings build() =>
      const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: false);
}

class _RecordingCellar extends CellarNotifier {
  final List<CourtPack> defined = [];
  final List<String> removed = [];

  @override
  Future<Cellar> build() async => throw UnimplementedError('the editor never reads the cellar');

  @override
  Future<PackProblem?> definePack(CourtPack pack) async {
    defined.add(pack);
    return null;
  }

  @override
  Future<void> removePack(String id) async => removed.add(id);
}

void main() {
  late _RecordingCellar wrote;

  Future<void> pumpEditor(
    WidgetTester tester, {
    required String derivedLabel,
    CourtPack? existing,
  }) async {
    wrote = _RecordingCellar();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeSettingsProvider.overrideWith(_FixedLocale.new),
          cellarProvider.overrideWith(() => wrote),
        ],
        child: MaterialApp(
          theme: HollowTheme.build(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPackEditor(
                  context,
                  packKey: 'iba/New Era',
                  derivedLabel: derivedLabel,
                  existing: existing,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // Discrete pumps rather than `pumpAndSettle`: the application schedules frames continuously, so waiting for a
    // quiet frame waits for one that never comes.
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('**naming an unnamed folder keeps the label it already had**', (tester) async {
    // Opening this on a folder nobody has named is how a pack is created, so saving without typing has to keep the
    // folder exactly as it looked rather than producing a nameless one.
    await pumpEditor(tester, derivedLabel: 'New Era');
    await tester.tap(find.byKey(const ValueKey('pack-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(wrote.defined, hasLength(1));
    expect(wrote.defined.single.id, 'iba/New Era');
    expect(wrote.defined.single.name, 'New Era');
  });

  testWidgets('**a rename, a note and a colour all reach the write path**', (tester) async {
    await pumpEditor(tester, derivedLabel: 'New Era');
    await tester.enterText(find.byKey(const ValueKey('pack-name')), '新时代');
    await tester.enterText(find.byKey(const ValueKey('pack-note')), '友方酒 · 2026 秋');
    await tester.enterText(find.byKey(const ValueKey('pack-accent')), '#8a5a32');
    await tester.enterText(find.byKey(const ValueKey('pack-order')), '20');
    await tester.tap(find.byKey(const ValueKey('pack-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final p = wrote.defined.single;
    expect(p.name, '新时代');
    expect(p.note, '友方酒 · 2026 秋');
    // **Normalised to upper case and with the hash**, so two readers typing the same colour get the same record.
    expect(p.accent, '#8A5A32');
    expect(p.order, 20);
  });

  group('what it refuses', () {
    testWidgets('**a colour that is not a colour is refused, and the field is named**', (tester) async {
      // The page falls back to gold when *drawing* an unparsable accent, because drawing has to survive bad data. A
      // form is where bad data is caught, so this says which field was wrong -- otherwise a reader who typed the hex
      // without its hash would save something that looked right and drew as gold.
      await pumpEditor(tester, derivedLabel: 'New Era');
      await tester.enterText(find.byKey(const ValueKey('pack-accent')), '8A5A3');
      await tester.tap(find.byKey(const ValueKey('pack-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.text(Copy.packAccentNotAColour.textFor('zh-Hans')), findsOneWidget);
      expect(wrote.defined, isEmpty, reason: 'a refused form must write nothing');
    });

    testWidgets('a colour without its hash is accepted and normalised', (tester) async {
      await pumpEditor(tester, derivedLabel: 'New Era');
      await tester.enterText(find.byKey(const ValueKey('pack-accent')), '8a5a32');
      await tester.tap(find.byKey(const ValueKey('pack-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(wrote.defined.single.accent, '#8A5A32');
    });

    testWidgets('a nameless folder is refused', (tester) async {
      await pumpEditor(tester, derivedLabel: 'New Era');
      await tester.enterText(find.byKey(const ValueKey('pack-name')), '   ');
      await tester.tap(find.byKey(const ValueKey('pack-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(find.text(Copy.packNeedsName.textFor('zh-Hans')), findsOneWidget);
      expect(wrote.defined, isEmpty);
    });
  });

  // **Two tests rather than one, and the first version was one.** It pumped the editor twice in a single body to
  // compare the named and unnamed cases -- which replaces the widget tree under the first half's expectations, and the
  // failure was `Found 0 widgets with key pack-delete` for the case that *should* have had one. A test that needs two
  // arrangements is two tests.
  testWidgets('delete is not offered for a folder nobody has named yet', (tester) async {
    await pumpEditor(tester, derivedLabel: 'New Era');
    expect(
      find.byKey(const ValueKey('pack-delete')),
      findsNothing,
      reason: 'there is nothing to remove until the reader has made the folder theirs',
    );
  });

  testWidgets('**delete is offered for a folder the reader made**', (tester) async {
    // `CourtPackEvents.removed` refuses the shipped pack's id, so offering the button for it would be offering one
    // that cannot work -- and the reader would find that out by pressing it.
    await pumpEditor(
      tester,
      derivedLabel: '新时代',
      existing: const CourtPack(id: 'iba/New Era', name: '新时代'),
    );
    expect(find.byKey(const ValueKey('pack-delete')), findsOneWidget);
  });

  testWidgets('**deleting says what happens to the recipes before it is pressed**', (tester) async {
    await pumpEditor(
      tester,
      derivedLabel: '新时代',
      existing: const CourtPack(id: 'iba/New Era', name: '新时代'),
    );
    expect(find.text(Copy.packDeleteKeepsRecipes.textFor('zh-Hans')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pack-delete')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(wrote.removed, ['iba/New Era']);
  });
}
