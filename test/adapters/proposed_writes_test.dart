import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/adapters/cellar_tools.dart';
import 'package:hollow_court/adapters/proposed_writes.dart';

/// The seven kinds of proposal, each read back as the write it becomes.
///
/// This is the test the cards did not have. Before it, the mapping lived in a switch inside a widget,
/// behind a provider and a pump, and nothing checked that a recount had not been wired to the discard
/// method -- a mistake that writes the wrong thing while the card looks exactly right.
void main() {
  test('a new bottle becomes an add', () {
    expect(
      writeFor(const AddBottle(sku: 'gin', millilitres: 700)),
      const WriteAddBottle('gin', 700),
    );
  });

  test('a recount carries the bottle and the new volume', () {
    expect(
      writeFor(const RecountBottle(bottleId: 'b-1', millilitres: 320)),
      const WriteRecountBottle('b-1', 320),
    );
  });

  test('a discard carries the bottle and the amount that leaves', () {
    expect(
      writeFor(const DiscardBottle(bottleId: 'b-1', millilitres: 60)),
      const WriteDiscardBottle('b-1', 60),
    );
  });

  test('a bottle rename stays on the bottle', () {
    expect(
      writeFor(const RenameBottle(bottleId: 'b-7', name: 'my rye')),
      const WriteRenameBottle('b-7', 'my rye'),
    );
  });

  test('an ingredient rename keeps no bottle id at all', () {
    // The two renames are separate writes because they act on different things. A test that only
    // checked "a rename happened" would pass while the bottle-level one landed on the vocabulary.
    final write = writeFor(const RenameIngredient(ingredientId: 'rye', name: '瑞伊威士忌'));
    expect(write, const WriteRenameIngredient('rye', '瑞伊威士忌'));
    expect(write, isNot(isA<WriteRenameBottle>()));
  });

  test('a new ingredient carries the name and the category', () {
    expect(
      writeFor(const NewIngredient(name: 'suze', category: 'bitter')),
      const WriteAuthorIngredient('suze', 'bitter'),
    );
  });

  test('a new recipe carries its items, and the method and glass it names', () {
    const items = [
      (ingredientId: 'gin', amount: '60', unit: 'ml'),
      (ingredientId: 'vermouth', amount: '20', unit: 'ml'),
    ];
    final write = writeFor(const NewRecipe(
      name: 'dry martini',
      items: items,
      method: 'stir',
      glass: 'coupe',
    ));
    expect(write, isA<WriteAuthorRecipe>());
    final recipe = write as WriteAuthorRecipe;
    expect(recipe.name, 'dry martini');
    expect(recipe.items.length, 2);
    expect(recipe.items.first.ingredientId, 'gin');
    expect(recipe.method, 'stir');
    expect(recipe.glass, 'coupe');
  });

  test('every proposal kind reaches a write of its own', () {
    // The point of the mapping: no two kinds share a target, so a case pointed at the wrong method
    // shows up as two kinds producing one write rather than as a card that looks fine.
    final writes = <CellarWrite>[
      writeFor(const AddBottle(sku: 'gin', millilitres: 700)),
      writeFor(const RecountBottle(bottleId: 'b-1', millilitres: 320)),
      writeFor(const DiscardBottle(bottleId: 'b-1', millilitres: 60)),
      writeFor(const RenameBottle(bottleId: 'b-7', name: 'my rye')),
      writeFor(const RenameIngredient(ingredientId: 'rye', name: '瑞伊威士忌')),
      writeFor(const NewIngredient(name: 'suze', category: 'bitter')),
      writeFor(const NewRecipe(name: 'dry martini', items: [])),
    ];
    expect(writes.map((write) => write.runtimeType).toSet().length, writes.length);
  });

  test('a volume leaves the proposal as the domain type', () {
    // Microlitres, because that is what the domain stores; 700 ml is 700000 of them.
    expect(volumeOf(700).microlitres, 700000);
  });
}
