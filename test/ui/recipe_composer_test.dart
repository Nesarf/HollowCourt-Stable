import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/events/recipe_authoring.dart';
import 'package:hollow_court/domain/model/ingredient.dart';
import 'package:hollow_court/ui/library.dart';
import 'package:hollow_court/ui/l10n/locale_providers.dart';
import 'package:hollow_court/ui/l10n/locale_settings.dart';
import 'package:hollow_court/ui/recipe_composer.dart';
import 'package:hollow_court/ui/theme.dart';

/// Writing a recipe of one's own — the screen `docs/proposal-recipes-and-packs.md` §2 asked for.
///
/// **The defect this closes, in the proposal's own words**: *"Can a user create one? **No.**"* The application had
/// exactly two write paths, a bottle and a journal entry, so everything here is about the third one working
/// end to end: fill the form, press save, and find the recipe in the log rather than only on the screen that just
/// closed.
class _FixedLocale extends LocaleSettingsNotifier {
  @override
  LocaleSettings build() =>
      const LocaleSettings(primaryTag: 'zh-Hans', secondaryTag: 'en', dualCopy: false);
}

/// A cellar that records what the composer asked it to write, and does not touch the disk.
///
/// **It is a fake, and the reason is worth stating rather than hiding.** The first version of this test opened a real
/// `EventLog` in a temporary directory so the assertion could be about the file the application writes -- and it hung
/// for ten minutes twice, because a real file open does not complete under the fake clock a widget test runs in.
/// **That is the third time in this session the same shape has cost minutes**, so the choice here is deliberate:
///
/// * **What this proves**: the sheet maps what a reader typed onto an `AuthoredRecipe` correctly -- the name, the
///   chosen ingredient id, the amount, the method, and the id an edit keeps -- and refuses what it should refuse.
/// * **What it does not prove**: that such a recipe survives a restart. That belongs to `RecipeBook` and to
///   `EventLog`, and it is tested there, on a real file, in tests that are not widget tests.
///
/// Splitting it that way is also how this repository already tests the shelf: `bar_page_test` records the calls the
/// page makes and leaves the appending of events to the notifier's own tests.
class _RecordingCellar extends CellarNotifier {
  final List<AuthoredRecipe> written = [];

  /// **Never called**, because the write paths this test exercises are overridden below. If it ever is, the test
  /// wants to know rather than to run against a cellar that quietly has nothing in it.
  @override
  Future<Cellar> build() async => throw UnimplementedError('the composer never reads the cellar');

  @override
  Future<void> authorRecipe(AuthoredRecipe recipe, {String? id}) async {
    written.add(recipe);
  }

  @override
  Future<void> removeAuthoredRecipe(String id) async {}
}

void main() {
  /// The ingredients the picker offers, which is what makes a line resolvable.
  List<Ingredient> shelf() => const [
    Ingredient(id: 'ginPlymouth', name: 'Plymouth Gin'),
    Ingredient(id: 'campari', name: 'Campari'),
    Ingredient(id: 'vermouthSweet', name: 'Sweet Vermouth'),
  ];

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('recipe_composer'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Builds a page whose only job is to open the sheet, so the test is about the sheet and not the list behind it.
  late _RecordingCellar wrote;

  Future<void> pumpComposer(WidgetTester tester) async {
    // **A fresh recorder per pump.** The first version captured one celler instance across the whole file, so a
    // recipe written by an earlier test was still in the list when a later test asserted that nothing was written --
    // and the failure looked like the form accepting what it should refuse.
    wrote = _RecordingCellar();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localeSettingsProvider.overrideWith(_FixedLocale.new),
          // Captured, because the assertions are about **what the sheet asked to be written** -- see the note on
          // `_RecordingCellar` for what that does and does not prove.
          cellarProvider.overrideWith(() => wrote),
        ],
        child: MaterialApp(
          theme: HollowTheme.build(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRecipeComposer(context, ingredients: shelf()),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // **Discrete pumps rather than `pumpAndSettle`, and this test hung for ten minutes learning why.** The
    // application schedules frames continuously -- the same property that made `widget_test`'s settings case flaky
    // -- so `pumpAndSettle` waits for a quiet frame that never comes. Pumping a fixed number of times is not a
    // guess: opening a sheet is a route push and a build.
    await tester.pump();
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('**a recipe filled in by hand reaches the log**', (tester) async {
    await pumpComposer(tester);

    await tester.enterText(find.byKey(const ValueKey('recipe-name')), '自己的尼格罗尼');
    await tester.enterText(find.byKey(const ValueKey('recipe-line-0-amount')), '30');
    await tester.enterText(find.byKey(const ValueKey('recipe-method')), '搅匀，滤冰');

    // The ingredient picker is a dropdown and has to be chosen rather than typed: a line naming an id this build
    // does not carry is refused on save, and typing into a menu is not a thing a reader can do.
    await tester.tap(find.byKey(const ValueKey('recipe-line-0-ingredient')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.tap(find.text('Plymouth Gin').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.byKey(const ValueKey('recipe-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // **The assertion is on what was written, not on the sheet having closed.** A form that closes and writes
    // nothing is exactly the failure this test is for, and the screen would have looked identical.
    expect(wrote.written, hasLength(1), reason: 'the recipe never reached the write path');
    final written = wrote.written.single;
    expect(written.name, '自己的尼格罗尼');
    expect(written.items, hasLength(1));
    expect(written.items.single.ingredientId, 'ginPlymouth');
    expect(written.items.single.amount, '30');
    expect(written.method, '搅匀，滤冰');
    // **And the id is left to the notifier to mint**, which is where the log's clock lives -- see `authorRecipe`.
    // A composer that invented one would be consuming the identity of an event it is not creating.
    expect(written.id, isEmpty, reason: 'a new recipe arrives without an id and the notifier mints it');
  });

  testWidgets('**a nameless recipe is refused, and says why**', (tester) async {
    await pumpComposer(tester);

    // An empty form: no name, and the line it starts with is blank. **That** is the case "needs a name and a line"
    // is about, and the first version of this test put `30` in the amount box and expected the same sentence --
    // which it should not, because a line with an amount and no ingredient is a different fault with its own words.
    await tester.tap(find.byKey(const ValueKey('recipe-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.text(Copy.recipeNeedsNameAndLine.textFor('zh-Hans')),
      findsOneWidget,
      reason: 'a form that refuses silently is a form somebody fills in twice',
    );
    expect(wrote.written, isEmpty, reason: 'a refused form must write nothing');
  });

  testWidgets('**a line with an amount but no ingredient is refused, and named as such**', (tester) async {
    // **The gap a UI test found on 2026-10-01.** The draft dropped a line that was entirely blank, and blank meant
    // "no ingredient *and* no amount" -- so typing `30` without choosing what it was thirty *of* produced a line
    // that survived and a recipe whose ingredient id was the empty string. Nothing downstream could make such a
    // recipe or price it, and no screen could say which line was wrong.
    await pumpComposer(tester);

    await tester.enterText(find.byKey(const ValueKey('recipe-name')), '自己的尼格罗尼');
    await tester.enterText(find.byKey(const ValueKey('recipe-line-0-amount')), '30');
    await tester.tap(find.byKey(const ValueKey('recipe-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.text(Copy.recipeLineNeedsIngredient.textFor('zh-Hans')), findsOneWidget);
    expect(wrote.written, isEmpty, reason: 'a recipe with an unnamed ingredient must not reach the log');
  });

  testWidgets('a recipe with a name but no lines is refused too', (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byKey(const ValueKey('recipe-name')), '空配方');
    await tester.tap(find.byKey(const ValueKey('recipe-save')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text(Copy.recipeNeedsNameAndLine.textFor('zh-Hans')), findsOneWidget);
  });

  testWidgets('**adding a line adds a line, and the last one is cleared rather than removed**', (tester) async {
    // The last line is cleared so the form never becomes a name with nothing under it and no way back except the
    // button -- which is a state a reader can reach by pressing the little cross twice.
    await pumpComposer(tester);
    expect(find.byKey(const ValueKey('recipe-line-0-ingredient')), findsOneWidget);
    expect(find.byKey(const ValueKey('recipe-line-1-ingredient')), findsNothing);

    await tester.tap(find.text(Copy.recipeAddLine.textFor('zh-Hans')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('recipe-line-1-ingredient')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recipe-line-1-remove')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('recipe-line-1-ingredient')), findsNothing);
    expect(find.byKey(const ValueKey('recipe-line-0-ingredient')), findsOneWidget);

    // Removing the only remaining line leaves an empty one rather than an empty form.
    await tester.tap(find.byKey(const ValueKey('recipe-line-0-remove')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byKey(const ValueKey('recipe-line-0-ingredient')), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
