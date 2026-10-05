import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/events/recipe_collection.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/model/recipe_collections.dart';
import 'package:hollow_court/ui/collection_editor.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/theme.dart';

/// Making a collection of one's own — what ④ was for.
///
/// **What this proves and what it does not, stated rather than implied**, which is the same split
/// `recipe_composer_test` records. This uses a recorder rather than a real `EventLog`: a real file open does not
/// complete under the fake clock a widget test runs in, and that cost ten minutes twice in this session. So it
/// proves the sheet maps what a reader typed and ticked onto a collection and its members, and that a refusal comes
/// back as a sentence. **It does not prove a collection survives a restart** — that belongs to
/// `RecipeCollections.of`, which tests it on real events.
class _FixedLocale extends LocaleSettingsNotifier {
  @override
  LocaleSettings build() =>
      const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: false);
}

class _RecordingCellar extends CellarNotifier {
  /// Every call the sheet made, in order.
  final List<(String id, String name, List<CollectionMember> members)> writes = [];

  /// What the next call answers with, so a refusal can be exercised without building a real cycle.
  CollectionProblem? refuses;

  @override
  Future<Cellar> build() async => throw UnimplementedError('the editor never reads the cellar');

  @override
  Future<CollectionProblem?> setCollection({
    required String id,
    required String name,
    required Iterable<CollectionMember> members,
  }) async {
    final list = members.toList(growable: false);
    writes.add((id, name, list));
    return refuses;
  }

  @override
  Future<void> clearCollection(String id) async {}
}

void main() {
  late _RecordingCellar wrote;

  Recipe recipe(String id, String name) => Recipe(id: id, name: name, packId: 'official', items: const []);

  Future<void> pumpEditor(
    WidgetTester tester, {
    RecipeCollections existing = RecipeCollections.none,
    RecipeCollection? editing,
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
                onPressed: () => showCollectionEditor(
                  context,
                  recipes: [recipe('ibaNegroni', 'Negroni'), recipe('ibaDaiquiri', 'Daiquiri')],
                  nameOf: (r) => r.name,
                  existing: existing,
                  editing: editing,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // **Discrete pumps rather than `pumpAndSettle`**: the application schedules frames continuously, so waiting for
    // a quiet frame waits for one that never comes.
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('**a named collection with the drinks ticked reaches the write path**', (tester) async {
    await pumpEditor(tester);

    await tester.enterText(find.byKey(const ValueKey('collection-name')), '我的午後');
    await tester.tap(find.byKey(const ValueKey('collection-member-r:ibaNegroni')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('collection-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(wrote.writes, hasLength(1), reason: 'the collection never reached the write path');
    final (_, name, members) = wrote.writes.single;
    expect(name, '我的午後');
    expect(members, hasLength(1));
    // **The member is the recipe, by its library id**, which is what the fold resolves against.
    expect((members.single as RecipeMember).recipeId, 'ibaNegroni');
  });

  testWidgets('**a nameless collection is refused, and says why**', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byKey(const ValueKey('collection-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text(Copy.collectionNeedsName.textFor('zh-Hans')), findsOneWidget);
    expect(wrote.writes, isEmpty, reason: 'a refused form must write nothing');
  });

  testWidgets('**a collection that would contain itself comes back as a sentence, not a stack overflow**', (tester) async {
    // `checkMembership` catches this before the event is written, because afterwards the loop is in the log and in
    // every synced copy of it -- and the fold listing the contents would recurse until the stack ran out.
    await pumpEditor(tester);
    wrote.refuses = const CollectionWouldContainItself(['own.a', 'own.b']);

    await tester.enterText(find.byKey(const ValueKey('collection-name')), '绕');
    await tester.tap(find.byKey(const ValueKey('collection-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text(Copy.collectionWouldContainItself.textFor('zh-Hans')), findsOneWidget);
  });

  testWidgets('unticking a member takes it out', (tester) async {
    await pumpEditor(tester);
    await tester.enterText(find.byKey(const ValueKey('collection-name')), 'x');
    await tester.tap(find.byKey(const ValueKey('collection-member-r:ibaNegroni')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('collection-member-r:ibaDaiquiri')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('collection-member-r:ibaNegroni')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('collection-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final (_, _, members) = wrote.writes.single;
    expect(members, hasLength(1));
    expect((members.single as RecipeMember).recipeId, 'ibaDaiquiri');
  });

  testWidgets('**a collection may hold another collection, and never itself**', (tester) async {
    // The self is excluded from the list rather than offered and then refused: a checkbox that cannot be ticked is
    // better than one whose ticking produces an error.
    final mine = RecipeCollection(id: 'own.mine', name: '我的', members: const []);
    final other = RecipeCollection(id: 'own.other', name: '別的', members: const []);
    await pumpEditor(
      tester,
      existing: RecipeCollections(collections: {mine.id: mine, other.id: other}, hiddenFolders: const {}),
      editing: mine,
    );

    expect(find.byKey(const ValueKey('collection-member-c:own.other')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('collection-member-c:own.mine')),
      findsNothing,
      reason: 'a collection is not offered as a member of itself',
    );
  });
}
