import 'package:hollow_court/domain/model/recipe.dart';
import 'package:hollow_court/domain/model/recipe_folders.dart';
import 'package:test/test.dart';

/// Recipes grouped into folders, which is how the IBA's list gets its own column.
void main() {
  Recipe drink(String id, String name, {String source = 'iba', String category = ''}) => Recipe(
    id: id,
    name: name,
    items: const [],
    extras: {if (source.isNotEmpty) 'source': source, if (category.isNotEmpty) 'category': category},
  );

  test('**the official list is its own folder, and it comes first**', () {
    final folders = foldersOf([
      drink('a', 'Zombie', source: 'someone', category: 'Their list'),
      drink('b', 'Alexander', category: 'The Unforgettables'),
    ]);
    expect(folders.first.isOfficial, isTrue);
    expect(folders.first.label, 'The Unforgettables');
    expect(folders.last.source, 'someone');
  });

  test('a source with several categories becomes several folders, in the order written', () {
    final folders = foldersOf([
      drink('a', 'Daiquiri', category: 'The Unforgettables'),
      drink('b', 'Cosmopolitan', category: 'Contemporary Classics'),
      drink('c', 'Bramble', category: 'New Era'),
    ]);
    expect(folders.map((f) => f.label).toList(),
        ['The Unforgettables', 'Contemporary Classics', 'New Era']);
  });

  test('and inside a folder the drinks are by name', () {
    final folders = foldersOf([
      drink('a', 'Negroni', category: 'The Unforgettables'),
      drink('b', 'Alexander', category: 'The Unforgettables'),
    ]);
    expect(folders.single.recipes.map((r) => r.name).toList(), ['Alexander', 'Negroni']);
  });

  test('**a drink with no source is not dropped**', () {
    // A grouping that silently hid a recipe would be worse than a folder that says nothing about where it
    // came from.
    final folders = foldersOf([drink('a', 'Mystery', source: '')]);
    expect(folders, hasLength(1));
    expect(folders.single.recipes.single.name, 'Mystery');
    expect(folders.single.isOfficial, isFalse);
  });

  test('no recipes is no folders, not one empty one', () {
    expect(foldersOf(const []), isEmpty);
  });
}
