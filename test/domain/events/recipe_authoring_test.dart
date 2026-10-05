import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/events/event.dart';
import 'package:hollow_court/domain/events/hlc.dart';
import 'package:hollow_court/domain/events/recipe_authoring.dart';

/// Recipes the reader wrote: what the log carries, and what it refuses.
///
/// **The shape under test is the whole design**: a reader's recipe is the *same record* as a shipped one, so one
/// page can hold both and one search can find both. What these tests hold is that the record survives a round trip
/// unchanged, that the refusals are refusals rather than silent stores, and that a shipped recipe cannot be
/// deleted by writing an event.
void main() {
  Hlc at(int millis, [int counter = 0]) =>
      Hlc(physicalMillis: millis, counter: counter, nodeId: 'test');

  AuthoredRecipe sample({String name = '自己的尼格罗尼', String? folder}) => AuthoredRecipe(
    id: AuthoredRecipeId.from(name, at(1000)),
    name: name,
    folder: folder,
    method: 'stirred, over ice',
    glass: 'rocks',
    items: const [
      AuthoredItem(ingredientId: 'ginPlymouth', amount: '30', unit: 'ml'),
      AuthoredItem(ingredientId: 'vermouthSweet', amount: '30', unit: 'ml'),
      AuthoredItem(ingredientId: 'campari', amount: '30', unit: 'ml', note: 'or a little less'),
    ],
  );

  group('the record survives the log', () {
    test('**every field comes back, including the optional ones**', () {
      // Written because a wire format that quietly drops a field is the failure nobody notices until a reader
      // says their note disappeared -- and a round trip is the only cheap way to catch it.
      final recipe = AuthoredRecipe(
        id: 'own.negroni-1000-0',
        name: '自己的尼格罗尼',
        subtitle: 'a house version',
        folder: 'own.collection.negroni-2000',
        description: 'less campari than the book says',
        method: 'stirred',
        glass: 'rocks',
        ice: 'one big cube',
        garnish: 'orange peel',
        items: const [
          AuthoredItem(ingredientId: 'ginPlymouth', amount: '30', unit: 'ml', role: 'base'),
          AuthoredItem(ingredientId: 'campari', amount: '1/2', unit: 'part', note: 'to taste'),
        ],
      );

      final event = RecipeAuthoredEvents.set(hlc: at(1), recipe: recipe);
      final read = RecipeAuthoredOp.tryParse(event)!;

      expect(read.recipe!.id, recipe.id);
      expect(read.recipe!.name, recipe.name);
      expect(read.recipe!.subtitle, recipe.subtitle);
      expect(read.recipe!.folder, recipe.folder);
      expect(read.recipe!.description, recipe.description);
      expect(read.recipe!.method, recipe.method);
      expect(read.recipe!.glass, recipe.glass);
      expect(read.recipe!.ice, recipe.ice);
      expect(read.recipe!.garnish, recipe.garnish);
      expect(read.recipe!.items.length, 2);
      expect(read.recipe!.items.first.role, 'base');
      // **The amount is a string and stays one.** `1/2` and `0.5` are the same drink and must not become two, which
      // is why the domain layer's refusal to carry floats outside itself is honoured at the wire too.
      expect(read.recipe!.items.last.amount, '1/2');
      expect(read.recipe!.items.last.note, 'to taste');
    });

    test('an absent optional field stays absent rather than becoming empty', () {
      // `null` and `''` are different claims: "no note was written" against "a note was written and left blank".
      final event = RecipeAuthoredEvents.set(hlc: at(1), recipe: sample());
      final read = RecipeAuthoredOp.tryParse(event)!;
      expect(read.recipe!.subtitle, isNull);
      expect(read.recipe!.garnish, isNull);
    });

    test('an event of a type this build does not know is not ours, and does not throw', () {
      // The overlay's rule, unchanged: a peer from a future version is carried untouched, so "not mine" is
      // ordinary. Only a malformed payload of a type we *do* know is an error.
      final foreign = Event(hlc: at(1), type: 'recipe.authored.somethingElse', data: const {});
      expect(RecipeAuthoredOp.tryParse(foreign), isNull);
    });

    test('a malformed payload of a known type throws instead of folding to nonsense', () {
      final broken = Event(hlc: at(1), type: RecipeAuthoredEvent.set, data: const {});
      expect(() => RecipeAuthoredOp.tryParse(broken), throwsA(isA<Object>()));
    });
  });

  group('what it refuses', () {
    test('**a nameless recipe is refused**', () {
      // A recipe nobody can find by name is not a recipe, and the application should not be able to store one.
      final recipe = sample(name: '   ');
      expect(validateAuthored(recipe, known: _known), contains(isA<RecipeUnnamed>()));
    });

    test('**a recipe with no ingredient lines is refused**', () {
      final recipe = AuthoredRecipe(id: 'own.x-1-0', name: '空的东西', items: const []);
      expect(validateAuthored(recipe, known: _known), contains(isA<RecipeEmpty>()));
    });

    test('an unknown ingredient is refused, and the id is named', () {
      // Refused rather than stored loosely: an unknown id folds to a recipe that can never be made and cannot be
      // priced, and the reader could not tell that from one they simply cannot make yet.
      final recipe = AuthoredRecipe(
        id: 'own.x-1-0',
        name: 'x',
        items: const [AuthoredItem(ingredientId: 'nobodyKnowsThis', amount: '10', unit: 'ml')],
      );
      final problems = validateAuthored(recipe, known: _known);
      expect(problems.whereType<RecipeUnknownIngredient>().single.ingredientId, 'nobodyKnowsThis');
    });

    test('**a line with an amount but no ingredient is refused**', () {
      // **Found by a UI test on 2026-10-01, and it is the kind of gap a form hides.** The composer dropped a line
      // that was entirely blank, and blank meant "no ingredient *and* no amount" -- so typing `30` without choosing
      // what it was thirty *of* survived the form and folded into a recipe whose ingredient id was the empty
      // string. Nothing downstream could make such a recipe or price it, and no screen could say which line was
      // wrong.
      final recipe = AuthoredRecipe(
        id: 'own.x-1-0',
        name: 'half filled in',
        items: const [AuthoredItem(ingredientId: '', amount: '30', unit: 'ml')],
      );
      final problems = validateAuthored(recipe, known: _known);
      final missing = problems.whereType<RecipeLineWithoutIngredient>().single;
      expect(missing.index, 1, reason: 'the form has to be able to point at the line');
    });

    test('a blank ingredient is not also reported as unknown', () {
      // Two complaints about one line would be two things a reader has to fix for one mistake.
      final recipe = AuthoredRecipe(
        id: 'own.x-1-0',
        name: 'x',
        items: const [AuthoredItem(ingredientId: '', amount: '30')],
      );
      final problems = validateAuthored(recipe, known: _known);
      expect(problems.whereType<RecipeUnknownIngredient>(), isEmpty);
    });

    test('**every problem is reported, not just the first**', () {
      // So a screen can say all of it at once rather than making somebody submit four times to learn four things.
      final recipe = AuthoredRecipe(
        id: 'own.x-1-0',
        name: '',
        items: const [AuthoredItem(ingredientId: 'nope', amount: '10')],
      );
      final problems = validateAuthored(recipe, known: _known);
      expect(problems.whereType<RecipeUnnamed>(), isNotEmpty);
      expect(problems.whereType<RecipeUnknownIngredient>(), isNotEmpty);
      // Empty is not among them: there *is* a line, it just names something unknown. Two different complaints.
      expect(problems.whereType<RecipeEmpty>(), isEmpty);
    });

    test('**a shipped recipe cannot be removed by writing an event**', () {
      // The guard is here rather than in a screen, so no build can make a drink vanish from the library by
      // recording that somebody asked for it to.
      expect(
        () => RecipeAuthoredEvents.removed(hlc: at(1), id: 'iba.negroni'),
        throwsArgumentError,
      );
      // And a reader's own id goes through.
      expect(
        RecipeAuthoredEvents.removed(hlc: at(1), id: 'own.mine-1-0').type,
        RecipeAuthoredEvent.removed,
      );
    });
  });

  group('the id', () {
    test('**is always the reader\'s own, whatever the name**', () {
      // The prefix is what keeps a reader's recipe from colliding with a shipped one. A collision would let one
      // overwrite the other, which looks like a save that did not work.
      for (final name in ['Negroni', '  ', '!!!', '自己的尼格罗尼', 'a' * 200]) {
        final id = AuthoredRecipeId.from(name, at(42));
        expect(AuthoredRecipeId.isMine(id), isTrue, reason: 'name $name produced $id');
      }
      expect(AuthoredRecipeId.isMine('iba.negroni'), isFalse);
    });

    test('is stable for the same name and clock, and differs across clocks', () {
      // **Deterministic on purpose.** Two devices that saw the same edit have to agree on what to call it, so the
      // id is derived rather than random.
      expect(AuthoredRecipeId.from('Negroni', at(42, 0)), AuthoredRecipeId.from('Negroni', at(42, 0)));
      expect(AuthoredRecipeId.from('Negroni', at(42, 1)), isNot(AuthoredRecipeId.from('Negroni', at(42, 0))));
      expect(AuthoredRecipeId.from('Negroni', at(43)), isNot(AuthoredRecipeId.from('Negroni', at(42))));
    });

    test('survives a filename: no separators, no spaces, nothing to escape', () {
      final id = AuthoredRecipeId.from('Gin & Tonic / 金汤力!', at(42));
      expect(id, isNot(contains(' ')));
      expect(id, isNot(contains('/')));
      expect(id, isNot(contains('&')));
      expect(id, matches(RegExp(r'^own\.[a-z0-9\u4e00-\u9fff-]+-\d+-\d+$')));
    });
  });
}

/// The ingredient ids these tests treat as resolvable.
const _known = <String>{'ginPlymouth', 'vermouthSweet', 'campari'};
