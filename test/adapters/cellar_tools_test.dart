import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/adapters/cellar_tools.dart';
import 'package:hollow_court/adapters/chat_client.dart';
import 'package:hollow_court/domain/model/ingredient.dart';
import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/units/rational.dart';

/// **The two tools that read rather than propose**, and the arithmetic one of them delegates to.
///
/// `recipe_strength` is the reason this file exists: the model could divide 24 by 90 itself and be right most of the
/// time, which is the worst kind of right. The domain has exact rational arithmetic and a dilution table per method,
/// and the tool exists so that the number a reader is told came from those rather than from a language model.
void main() {
  Ingredient gin() => Ingredient(id: 'gin', name: '琴酒', abvPercent: Rational.fromInt(40));
  const Ingredient lime = Ingredient(id: 'juiceLime', name: '青柠汁');

  Recipe gimlet() => Recipe(
    id: 'gimlet',
    name: '琴蕾',
    method: Method.stirred,
    items: const <RecipeItem>[
      RecipeItem(ingredientId: 'gin', amount: 60000),
      RecipeItem(ingredientId: 'juiceLime', amount: 30000),
    ],
    methodSteps: const <String>['加冰搅匀', '滤入杯中'],
  );

  CellarToolBox box() => CellarToolBox(
    ingredients: <Ingredient>[gin(), lime],
    recipes: <Recipe>[gimlet()],
  );

  Future<String> run(String name, [Map<String, Object?> arguments = const <String, Object?>{}]) =>
      box().run(ChatToolCall(id: 'c1', name: name, arguments: arguments));

  test('**read_recipe reads one recipe with the library names and millilitres**', () async {
    final answer = await run('read_recipe', <String, Object?>{'name': '琴蕾'});
    expect(answer, contains('琴蕾'));
    expect(answer, contains('琴酒'));
    expect(answer, contains('60 ml'));
    expect(answer, contains('青柠汁'));
    expect(answer, contains('30 ml'));
    expect(answer, contains('stirred'));
    expect(answer, contains('加冰搅匀'));
  });

  test('a recipe answers to its id as well as its name', () async {
    expect(await run('read_recipe', <String, Object?>{'name': 'gimlet'}), contains('琴蕾'));
  });

  test('**a name nobody has is said plainly, with the way to find one**', () async {
    final answer = await run('read_recipe', <String, Object?>{'name': '不存在的酒'});
    expect(answer, contains('不存在的酒'));
    expect(answer, contains('read_recipes'));
  });

  test('**recipe_strength goes through the domain arithmetic, not through a guess**', () async {
    // 60 ml at 40% is 24 ml of alcohol in 90 ml of liquid: 26.7%. Stirring adds the midpoint of 15 to 20 percent
    // water, so 105.75 ml and 22.7%. Both figures come from `dosing/abv.dart` and `dosing/dilution.dart`.
    final answer = await run('recipe_strength', <String, Object?>{'name': '琴蕾'});
    expect(answer, contains('26.7'));
    expect(answer, contains('22.7'));
    expect(answer, contains('90 ml'));
  });

  test('**an ingredient with no figure is named rather than quietly counted as nothing**', () async {
    final answer = await run('recipe_strength', <String, Object?>{'name': '琴蕾'});
    expect(answer, contains('青柠汁'));
    expect(answer, contains('没写酒精度'));
  });

  test('**a recipe with no method is treated as built, which adds no water**', () async {
    final plain = CellarToolBox(
      ingredients: <Ingredient>[gin()],
      recipes: <Recipe>[
        Recipe(
          id: 'shot',
          name: '一口',
          items: const <RecipeItem>[RecipeItem(ingredientId: 'gin', amount: 30000)],
        ),
      ],
    );
    final answer = await plain.run(
      ChatToolCall(id: 'c', name: 'recipe_strength', arguments: <String, Object?>{'name': '一口'}),
    );
    expect(answer, contains('built'));
    // The same figure twice: there is no ice, so nothing was added to the glass.
    final figures = RegExp(r'\d+\.\d%').allMatches(answer).map((match) => match.group(0)).toSet();
    expect(figures, hasLength(1));
  });

  test('both tools ask for a name rather than answering about nothing', () async {
    expect(await run('read_recipe'), contains('name or id'));
    expect(await run('recipe_strength'), contains('name or id'));
  });
}
