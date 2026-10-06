import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/events/ingredient_authoring.dart';
import 'package:hollow_court/ui/ingredient_editor.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/theme.dart';

/// Adding an ingredient of one's own -- stage ③'s screen.
///
/// **What this proves and what it does not**, the split `collection_editor_test` and `pack_editor_test` already
/// record: a recorder rather than a real `EventLog`, because a real file open does not complete under the fake clock a
/// widget test runs in. So it proves the sheet maps what a reader typed onto an `AuthoredIngredient` and refuses what
/// it should; it does not prove one survives a restart, which belongs to `IngredientBook.of` on real events.
class _FixedLocale extends LocaleSettingsNotifier {
  @override
  LocaleSettings build() =>
      const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: false);
}

class _RecordingCellar extends CellarNotifier {
  final List<AuthoredIngredient> written = [];
  final List<String?> ids = [];
  final List<String> removed = [];

  @override
  Future<Cellar> build() async => throw UnimplementedError('the editor never reads the cellar');

  @override
  Future<void> authorIngredient(AuthoredIngredient ingredient, {String? id}) async {
    written.add(ingredient);
    ids.add(id);
  }

  @override
  Future<void> removeAuthoredIngredient(String id) async => removed.add(id);
}

void main() {
  late _RecordingCellar wrote;

  Future<void> pumpEditor(WidgetTester tester, {AuthorIngredientView? editing}) async {
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
                onPressed: () => showIngredientEditor(context, editing: editing),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // Discrete pumps rather than `pumpAndSettle`: the application schedules frames continuously.
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('**a name, a kind, aliases and a note reach the write path**', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const ValueKey('ingredient-name')), '梅酒');
    await tester.enterText(find.byKey(const ValueKey('ingredient-kind')), 'liqueur');
    await tester.enterText(find.byKey(const ValueKey('ingredient-aliases')), '梅酒, うめしゅ');
    await tester.enterText(find.byKey(const ValueKey('ingredient-note')), '邻居自己泡的');
    await tester.tap(find.byKey(const ValueKey('ingredient-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final i = wrote.written.single;
    expect(i.name, '梅酒');
    expect(i.category, 'liqueur');
    expect(i.aliases, ['梅酒', 'うめしゅ']);
    expect(i.note, '邻居自己泡的');
    // **No id is passed for a new ingredient**, so the notifier mints one from the log's own clock -- taking a clock
    // reading is the log's business rather than a widget's.
    expect(wrote.ids.single, isNull);
  });

  testWidgets('**the kind is free text, so a shape the build does not carry is allowed**', (tester) async {
    // The proposal's design: the kinds are data, so a reader can add 茶 or 酊剂 the way they add a collection. A closed
    // enum would mean a build to add a shape.
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const ValueKey('ingredient-name')), '酊剂');
    await tester.enterText(find.byKey(const ValueKey('ingredient-kind')), 'tincture');
    await tester.tap(find.byKey(const ValueKey('ingredient-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(wrote.written.single.category, 'tincture');
  });

  testWidgets('an empty kind is absent rather than empty', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const ValueKey('ingredient-name')), 'x');
    await tester.tap(find.byKey(const ValueKey('ingredient-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(wrote.written.single.category, isNull);
  });

  testWidgets('**a blank name is refused, and nothing is written**', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('ingredient-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text(Copy.ingredientNeedsName.textFor('zh-Hans')), findsOneWidget);
    expect(wrote.written, isEmpty);
  });

  testWidgets('a trailing comma does not become an empty alias', (tester) async {
    // An empty alias would be a name the ingredient answers to that is the empty string, which matches everything.
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const ValueKey('ingredient-name')), 'x');
    await tester.enterText(find.byKey(const ValueKey('ingredient-aliases')), 'a, , b,');
    await tester.tap(find.byKey(const ValueKey('ingredient-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(wrote.written.single.aliases, ['a', 'b']);
  });

  testWidgets('delete is not offered for one the library ships', (tester) async {
    // `IngredientAuthoredEvents.removed` refuses an id that is not `own.`-prefixed, so offering the button would be
    // offering one that cannot work.
    await pumpEditor(
      tester,
      editing: const AuthorIngredientView(id: 'ginPlymouth', name: 'Plymouth Gin', kind: 'spirit', isMine: false),
    );
    expect(find.byKey(const ValueKey('ingredient-delete')), findsNothing);
  });

  testWidgets('**delete is offered for the reader\'s own, and says what it costs first**', (tester) async {
    await pumpEditor(
      tester,
      editing: const AuthorIngredientView(id: 'own.ume-1-0', name: '梅酒', kind: 'liqueur', isMine: true),
    );
    expect(find.byKey(const ValueKey('ingredient-delete')), findsOneWidget);
    // A recipe or a bottle may name this ingredient and those references are not rewritten, so the reader is told
    // what they will be left with rather than finding out on the shelf.
    expect(find.text(Copy.ingredientDeleteKeepsReferences.textFor('zh-Hans')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('ingredient-delete')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(wrote.removed, ['own.ume-1-0']);
  });

  testWidgets('editing the reader\'s own keeps its id', (tester) async {
    await pumpEditor(
      tester,
      editing: const AuthorIngredientView(id: 'own.ume-1-0', name: '梅酒', kind: 'liqueur', isMine: true),
    );
    await tester.enterText(find.byKey(const ValueKey('ingredient-name')), '梅酒（新）');
    await tester.tap(find.byKey(const ValueKey('ingredient-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(wrote.ids.single, 'own.ume-1-0');
    expect(wrote.written.single.id, 'own.ume-1-0');
  });
}
