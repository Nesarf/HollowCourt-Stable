// The tools the application hands her, and the one rule every one of them obeys: she reads, the reader acts.
//
// "一定程度上帮助打理" is read here as: she may look at the cellar and say exactly what should change, and every change
// is a sentence the reader carries out -- not a write performed behind their back. A model with write access to a
// stock ledger is one bad turn away from a cellar nobody can explain, and the ledger is the whole point of this
// application.
//
// So every mutating tool is named `propose_...`, it writes nothing, and what it does is put a pending change in front
// of the reader. The proposals are a sealed set rather than a loose map, because the screen has to draw one and
// execute it, and a typo in a string key would be a button that does nothing.

import 'dart:convert';

import '../adapters/chat_client.dart';
import '../domain/events/stock.dart';
import '../domain/model/ingredient.dart';

/// **One change she wants the reader to make.** Nothing here performs it; the screen does, through the same methods
/// the rest of the application uses.
sealed class PendingChange {
  const PendingChange();
}

/// Record a new bottle.
final class AddBottle extends PendingChange {
  const AddBottle({required this.sku, required this.millilitres});
  final String sku;
  final int millilitres;
}

/// Set what is actually left in a bottle that already exists.
final class RecountBottle extends PendingChange {
  const RecountBottle({required this.bottleId, required this.millilitres});
  final String bottleId;
  final int millilitres;
}

/// Pour the rest of a bottle away.
final class DiscardBottle extends PendingChange {
  const DiscardBottle({required this.bottleId, required this.millilitres});
  final String bottleId;
  final int millilitres;
}

/// Describe a new ingredient the library does not carry.
final class NewIngredient extends PendingChange {
  const NewIngredient({required this.name, this.category});
  final String name;
  final String? category;
}

/// Write a recipe the library does not carry.
///
/// **The amounts are strings, not numbers**, and that is the domain's own decision: `1/2` and `0.5` are the same drink
/// and must not become two. So the tool takes what a person would write and the model is asked to write it the same
/// way, rather than being asked to pick a unit and divide.
final class NewRecipe extends PendingChange {
  const NewRecipe({
    required this.name,
    required this.items,
    this.method,
    this.glass,
  });

  final String name;
  final List<({String ingredientId, String amount, String? unit})> items;
  final String? method;
  final String? glass;
}

/// The tools, the data they read, and the proposals they produce.
class CellarToolBox {
  const CellarToolBox({
    this.stock = const <BottleState>[],
    this.ingredients = const <Ingredient>[],
    this.recipeNames = const <({String id, String name})>[],
  });

  /// **What is on the shelves, as the ledger holds it** -- `cellar.stock.bottles`, passed through rather than copied
  /// into another shape, so the numbers she reads are the numbers the screen shows.
  final Iterable<BottleState> stock;
  final List<Ingredient> ingredients;
  final List<({String id, String name})> recipeNames;

  static List<Map<String, Object?>> get tools => <Map<String, Object?>>[
        webSearchToolDefinition,
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': 'read_cellar',
            'description': 'List what is on the shelves: the bottle id, the ingredient and how much is left. Use the '
                'bottle id with the propose tools. Returns at most fifty rows.',
            'parameters': <String, Object?>{'type': 'object', 'properties': <String, Object?>{}},
          },
        },
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': 'read_recipes',
            'description': 'List the recipes this cellar knows, by name and id. Use it when asked what can be made.',
            'parameters': <String, Object?>{'type': 'object', 'properties': <String, Object?>{}},
          },
        },
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': 'propose_add_bottle',
            'description': 'Propose recording one bottle. This writes nothing: it puts the proposal in front of the '
                'reader, who decides.',
            'parameters': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'sku': <String, Object?>{
                  'type': 'string',
                  'description': 'The ingredient id, taken from read_cellar or read_recipes. Never invent one.',
                },
                'millilitres': <String, Object?>{
                  'type': 'integer',
                  'description': 'How many millilitres the bottle holds.',
                },
              },
              'required': <String>['sku', 'millilitres'],
            },
          },
        },
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': 'propose_new_ingredient',
            'description': 'Propose adding an ingredient the library does not have -- the bottle a neighbour makes, '
                'something bought at a market. This writes nothing.',
            'parameters': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'name': <String, Object?>{'type': 'string', 'description': 'What the reader calls it.'},
                'category': <String, Object?>{
                  'type': 'string',
                  'description': 'Optional: spirit, liqueur, wine, beer, mixer, syrup, bitters, garnish, other.',
                },
              },
              'required': <String>['name'],
            },
          },
        },
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': 'propose_new_recipe',
            'description': 'Propose writing a recipe. Every ingredient must already exist in the library; use '
                'read_cellar or read_recipes to get real ids. Amounts are written the way a person writes them '
                '(“30”, “1/2”, “2 dash”) with a separate unit. This writes nothing.',
            'parameters': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'name': <String, Object?>{'type': 'string', 'description': 'What the drink is called.'},
                'method': <String, Object?>{
                  'type': 'string',
                  'description': 'Optional: shaken, stirred, built -- free text, never a closed list.',
                },
                'glass': <String, Object?>{'type': 'string', 'description': 'Optional: what it is served in.'},
                'items': <String, Object?>{
                  'type': 'array',
                  'description': 'At least one ingredient.',
                  'items': <String, Object?>{
                    'type': 'object',
                    'properties': <String, Object?>{
                      'ingredient': <String, Object?>{'type': 'string', 'description': 'The ingredient id.'},
                      'amount': <String, Object?>{'type': 'string', 'description': 'As written: 30, 1/2, 2.'},
                      'unit': <String, Object?>{'type': 'string', 'description': 'ml, oz, dash, piece.'},
                    },
                    'required': <String>['ingredient', 'amount'],
                  },
                },
              },
              'required': <String>['name', 'items'],
            },
          },
        },
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': 'propose_recount_bottle',
            'description': 'Propose correcting how much is left in a bottle the reader has just looked at. This '
                'writes nothing.',
            'parameters': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'bottle': <String, Object?>{'type': 'string', 'description': 'The bottle id from read_cellar.'},
                'millilitres': <String, Object?>{
                  'type': 'integer',
                  'description': 'What is actually left, as read off the bottle.',
                },
              },
              'required': <String>['bottle', 'millilitres'],
            },
          },
        },
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': 'propose_discard_bottle',
            'description': 'Propose pouring away what is left in a bottle -- broken, spoiled, or finished. This '
                'writes nothing.',
            'parameters': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'bottle': <String, Object?>{'type': 'string', 'description': 'The bottle id from read_cellar.'},
                'millilitres': <String, Object?>{
                  'type': 'integer',
                  'description': 'How much is being poured away.',
                },
              },
              'required': <String>['bottle', 'millilitres'],
            },
          },
        },
      ];

  /// Runs one call and answers with text for the model. **Never throws**: a tool that failed is a fact the model
  /// should be told, not an exception that kills the turn.
  Future<String> run(
    ChatToolCall call, {
    Future<String> Function(String query)? search,
    void Function(PendingChange change)? propose,
  }) async {
    switch (call.name) {
      case 'web_search':
        final query = '${call.arguments['query'] ?? ''}'.trim();
        if (query.isEmpty) return 'No query was given.';
        if (search == null) return 'The web search is not configured.';
        return search(query);

      case 'read_cellar':
        if (stock.isEmpty) return 'The cellar is empty.';
        final rows = stock.take(50).map((bottle) {
          final name = ingredients
                  .where((ingredient) => ingredient.id == bottle.sku)
                  .map((ingredient) => ingredient.name)
                  .firstOrNull ??
              bottle.sku;
          final millilitres = (bottle.remaining.microlitres / 1000).round();
          return '$name · $millilitres ml · bottle: ${bottle.bottleId} · ingredient: ${bottle.sku}';
        });
        return rows.join('\n');

      case 'read_recipes':
        if (recipeNames.isEmpty) return 'No recipes are loaded.';
        return recipeNames.map((recipe) => '${recipe.id} · ${recipe.name}').join('\n');

      case 'propose_add_bottle':
        final sku = '${call.arguments['sku'] ?? ''}'.trim();
        final millilitres = (call.arguments['millilitres'] as num?)?.toInt() ?? 0;
        if (sku.isEmpty || millilitres <= 0) return 'The proposal needs a sku and a volume in millilitres.';
        if (propose == null) return 'The proposal cannot be shown here.';
        // **Checked against the library, because a model that invents a sku would create a bottle nothing can match.**
        if (ingredients.isNotEmpty && !ingredients.any((ingredient) => ingredient.id == sku)) {
          return 'No ingredient has the id $sku. Use read_cellar or read_recipes and pick a real one.';
        }
        propose(AddBottle(sku: sku, millilitres: millilitres));
        return 'Proposed: a new $sku bottle, $millilitres ml. The reader decides whether to record it.';

      case 'propose_new_ingredient':
        final name = '${call.arguments['name'] ?? ''}'.trim();
        if (name.isEmpty) return 'The proposal needs a name.';
        if (propose == null) return 'The proposal cannot be shown here.';
        if (ingredients.any((ingredient) => ingredient.name == name)) {
          // **Refused, because a second ingredient with the same name is a library nobody can search.** The reader
          // would then own two "梅酒" and no way to tell which is which.
          return 'The library already has an ingredient called $name.';
        }
        final category = '${call.arguments['category'] ?? ''}'.trim();
        propose(NewIngredient(name: name, category: category.isEmpty ? null : category));
        return 'Proposed: a new ingredient, $name. The reader decides.';

      case 'propose_new_recipe':
        final name = '${call.arguments['name'] ?? ''}'.trim();
        if (name.isEmpty) return 'The proposal needs a name.';
        if (propose == null) return 'The proposal cannot be shown here.';
        if (recipeNames.any((recipe) => recipe.name == name)) {
          return 'A recipe called $name already exists.';
        }
        final raw = call.arguments['items'];
        if (raw is! List || raw.isEmpty) return 'A recipe needs at least one ingredient.';
        final items = <({String ingredientId, String amount, String? unit})>[];
        for (final entry in raw) {
          if (entry is! Map) continue;
          final id = '${entry['ingredient'] ?? ''}'.trim();
          final amount = '${entry['amount'] ?? ''}'.trim();
          final unit = '${entry['unit'] ?? ''}'.trim();
          if (id.isEmpty || amount.isEmpty) return 'Every item needs an ingredient id and an amount.';
          // **The id is checked against what actually exists**, because an invented one writes a recipe whose line
          // can never be matched to a bottle -- and the failure would appear days later as "unmakable for no reason".
          if (ingredients.isNotEmpty && !ingredients.any((ingredient) => ingredient.id == id)) {
            return 'No ingredient has the id $id. Use read_cellar or read_recipes and pick real ones.';
          }
          items.add((ingredientId: id, amount: amount, unit: unit.isEmpty ? null : unit));
        }
        if (items.isEmpty) return 'A recipe needs at least one ingredient.';
        final method = '${call.arguments['method'] ?? ''}'.trim();
        final glass = '${call.arguments['glass'] ?? ''}'.trim();
        propose(NewRecipe(
          name: name,
          items: items,
          method: method.isEmpty ? null : method,
          glass: glass.isEmpty ? null : glass,
        ));
        return 'Proposed: a recipe called $name with ${items.length} ingredients. The reader decides.';

      case 'propose_recount_bottle':
      case 'propose_discard_bottle':
        final bottleId = '${call.arguments['bottle'] ?? ''}'.trim();
        final millilitres = (call.arguments['millilitres'] as num?)?.toInt() ?? 0;
        if (bottleId.isEmpty || millilitres <= 0) {
          return 'The proposal needs a bottle id and a volume in millilitres.';
        }
        if (propose == null) return 'The proposal cannot be shown here.';
        final known = stock.where((bottle) => bottle.bottleId == bottleId).firstOrNull;
        if (known == null) {
          return 'No bottle has the id $bottleId. Use read_cellar and pick one that exists.';
        }
        final left = (known.remaining.microlitres / 1000).round();
        if (millilitres > left) {
          // **Refused here rather than at the button.** If the reader really did find more than the ledger says, that
          // is a different correction; letting the model quietly propose it would teach nobody anything.
          return 'That bottle has only $left ml left, so $millilitres ml cannot be recounted or poured away.';
        }
        final recounting = call.name == 'propose_recount_bottle';
        propose(recounting
            ? RecountBottle(bottleId: bottleId, millilitres: millilitres)
            : DiscardBottle(bottleId: bottleId, millilitres: millilitres));
        return 'Proposed: ${recounting ? 'recount' : 'discard'} $millilitres ml of $bottleId. The reader decides.';

      default:
        return 'No such tool: ${call.name}.';
    }
  }

  /// The whole cellar as one line, for the disclosure to count and the tests to check.
  String get summary => jsonEncode(<String, Object?>{
        'bottles': stock.length,
        'ingredients': ingredients.length,
        'recipes': recipeNames.length,
      });
}

/// The same definition as `web_search.dart`, named here so the tool list reads as one thing.
const Map<String, Object?> webSearchToolDefinition = <String, Object?>{
  'type': 'function',
  'function': <String, Object?>{
    'name': 'web_search',
    'description': 'Search the live web. Use it for anything about the present day: prices, releases, news, whether a '
        'distillery still exists. Do not use it for the reader\'s own cellar -- read_cellar is for that.',
    'parameters': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'query': <String, Object?>{
          'type': 'string',
          'description': 'The search query, 1 to 128 characters. Supports site:, lang:, after: and quotes.',
        },
      },
      'required': <String>['query'],
    },
  },
};
