import '../domain/units/quantity.dart';
import 'cellar_tools.dart';

/// The write a confirmed proposal becomes, as a value rather than as a call.
///
/// WHY THIS EXISTS. The mapping from a proposal to a write is the part that can be wrong: a case wired to
/// the wrong method writes the wrong thing -- a recount that becomes a discard, a rename that lands on the
/// bottle instead of the ingredient -- and nothing about the card looks different when it happens. In the
/// widget the mapping is buried behind a provider, a container and a pump, which is why it had no test;
/// stated as a value it can be read back directly.
///
/// The interface turns these into calls; it does not decide which call.
sealed class CellarWrite {
  const CellarWrite();
}

/// One bottle goes on the shelf.
final class WriteAddBottle extends CellarWrite {
  const WriteAddBottle(this.sku, this.millilitres);
  final String sku;
  final int millilitres;

  @override
  bool operator ==(Object other) =>
      other is WriteAddBottle && other.sku == sku && other.millilitres == millilitres;

  @override
  int get hashCode => Object.hash('add', sku, millilitres);

  @override
  String toString() => 'add $millilitres ml of $sku';
}

/// One bottle's remaining volume is corrected.
final class WriteRecountBottle extends CellarWrite {
  const WriteRecountBottle(this.bottleId, this.millilitres);
  final String bottleId;
  final int millilitres;

  @override
  bool operator ==(Object other) =>
      other is WriteRecountBottle && other.bottleId == bottleId && other.millilitres == millilitres;

  @override
  int get hashCode => Object.hash('recount', bottleId, millilitres);

  @override
  String toString() => 'recount $bottleId to $millilitres ml';
}

/// Part of one bottle leaves the shelf.
final class WriteDiscardBottle extends CellarWrite {
  const WriteDiscardBottle(this.bottleId, this.millilitres);
  final String bottleId;
  final int millilitres;

  @override
  bool operator ==(Object other) =>
      other is WriteDiscardBottle && other.bottleId == bottleId && other.millilitres == millilitres;

  @override
  int get hashCode => Object.hash('discard', bottleId, millilitres);

  @override
  String toString() => 'discard $millilitres ml from $bottleId';
}

/// One bottle gets a name the reader prefers.
final class WriteRenameBottle extends CellarWrite {
  const WriteRenameBottle(this.bottleId, this.name);
  final String bottleId;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is WriteRenameBottle && other.bottleId == bottleId && other.name == name;

  @override
  int get hashCode => Object.hash('rename-bottle', bottleId, name);

  @override
  String toString() => 'rename $bottleId to $name';
}

/// A word changes everywhere it appears.
final class WriteRenameIngredient extends CellarWrite {
  const WriteRenameIngredient(this.ingredientId, this.name);
  final String ingredientId;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is WriteRenameIngredient && other.ingredientId == ingredientId && other.name == name;

  @override
  int get hashCode => Object.hash('rename-ingredient', ingredientId, name);

  @override
  String toString() => 'rename $ingredientId to $name everywhere';
}

/// One ingredient is added to the library.
final class WriteAuthorIngredient extends CellarWrite {
  const WriteAuthorIngredient(this.name, this.category);
  final String name;
  final String? category;

  @override
  bool operator ==(Object other) =>
      other is WriteAuthorIngredient && other.name == name && other.category == category;

  @override
  int get hashCode => Object.hash('ingredient', name, category);

  @override
  String toString() => 'add the ingredient $name';
}

/// One recipe is added to the library.
final class WriteAuthorRecipe extends CellarWrite {
  const WriteAuthorRecipe(this.name, this.items, this.method, this.glass);
  final String name;
  final List<({String ingredientId, String amount, String? unit})> items;
  final String? method;
  final String? glass;

  @override
  bool operator ==(Object other) =>
      other is WriteAuthorRecipe &&
      other.name == name &&
      other.method == method &&
      other.glass == glass &&
      other.items.length == items.length;

  @override
  int get hashCode => Object.hash('recipe', name, method, glass, items.length);

  @override
  String toString() => 'add the recipe $name (${items.length} items)';
}

/// Read a proposal as the write it asks for.
///
/// Every case is a different method on the cellar, and this is the one place that says which. The
/// volumes become `Volume` here rather than in the widget, so a caller that forgets to convert cannot
/// exist.
CellarWrite writeFor(PendingChange proposal) => switch (proposal) {
      AddBottle(:final sku, :final millilitres) => WriteAddBottle(sku, millilitres),
      RecountBottle(:final bottleId, :final millilitres) => WriteRecountBottle(bottleId, millilitres),
      DiscardBottle(:final bottleId, :final millilitres) => WriteDiscardBottle(bottleId, millilitres),
      RenameBottle(:final bottleId, :final name) => WriteRenameBottle(bottleId, name),
      RenameIngredient(:final ingredientId, :final name) => WriteRenameIngredient(ingredientId, name),
      NewRecipe(:final name, :final items, :final method, :final glass) =>
        WriteAuthorRecipe(name, items, method, glass),
      NewIngredient(:final name, :final category) => WriteAuthorIngredient(name, category),
    };

/// The volume a write carries, as the domain's own type.
///
/// Kept beside [writeFor] because microlitres arrive as an `int` in the proposal and must not travel
/// any further as one.
Volume volumeOf(int millilitres) => Volume.fromMillilitres(millilitres);
