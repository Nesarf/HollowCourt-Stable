// // **The tools the application hands her, and the one rule every one of them obeys: she reads, the reader acts.**
//
// That rule is the owner's decision of 2026-09-26 kept intact while his decision of 2026-10-22 widened what she can
// do. "一定程度上帮助打理" is read here as: she may look at the cellar and say exactly what should change, and every
// change is a sentence the reader carries out -- not a write performed behind their back. A model with write access
// to a stock ledger is one bad turn away from a cellar nobody can explain, and the ledger is the whole point of this
// application.
//
// So the tool list is deliberately short: what is in the cellar, what one bottle is, what the web says, and what
// recipes exist. Four reads. A write tool would need its own consent, its own audit trail and its own tests, and that
// is a different piece of work rather than another entry in this list.

import 'dart:convert';

import '../adapters/chat_client.dart';
import '../domain/events/stock.dart';
import '../domain/model/ingredient.dart';

// A bottle, as a tool result describes it: the fields a person would read off a label plus what the ledger knows.
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

  /// The tool definitions, in the shape the API wants.
  static List<Map<String, Object?>> get tools => <Map<String, Object?>>[
        webSearchToolDefinition,
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': 'read_cellar',
            'description': 'List what is on the shelves: ingredient id, name and remaining volume. Use it before '
                'advising on what can be made. Returns at most fifty rows.',
            'parameters': <String, Object?>{'type': 'object', 'properties': <String, Object?>{}},
          },
        },
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': 'propose_add_bottle',
            'description': 'Propose recording one bottle. This does NOT write anything: it puts the proposal in '
                'front of the reader, who decides. Use it when the reader asks you to record what they bought, '
                'and say in your own answer what you proposed.',
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
            'name': 'read_recipes',
            'description': 'List the recipes this cellar knows, by name and id. Use it when asked what can be made.',
            'parameters': <String, Object?>{'type': 'object', 'properties': <String, Object?>{}},
          },
        },
      ];

  /// Runs one call and answers with text for the model. **Never throws**: a tool that failed is a fact the model
  /// should be told, not an exception that kills the turn.
  Future<String> run(
    ChatToolCall call, {
    Future<String> Function(String query)? search,
    void Function(BottleProposal proposal)? propose,
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
          return '$name · $millilitres ml · id: ${bottle.sku}';
        });
        return rows.join('\n');
      case 'propose_add_bottle':
        final sku = '${call.arguments['sku'] ?? ''}'.trim();
        final millilitres = (call.arguments['millilitres'] as num?)?.toInt() ?? 0;
        if (sku.isEmpty || millilitres <= 0) return 'The proposal needs a sku and a volume in millilitres.';
        if (propose == null) return 'The proposal cannot be shown here.';
        // **Checked against the library, because a model that invents a sku would create a bottle nothing can match.**
        final known = ingredients.any((ingredient) => ingredient.id == sku);
        if (ingredients.isNotEmpty && !known) {
          return 'No ingredient has the id $sku. Use read_cellar or read_recipes and pick a real one.';
        }
        propose(BottleProposal(sku: sku, millilitres: millilitres));
        return 'Proposed: $sku, $millilitres ml. The reader decides whether to record it.';

      case 'read_recipes':
        if (recipeNames.isEmpty) return 'No recipes are loaded.';
        return recipeNames.map((recipe) => '${recipe.id} · ${recipe.name}').join('\n');
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

// The same definition as `web_search.dart`, named here so the tool list reads as one thing.
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

// One bottle she wants the reader to record. Not written here, and deliberately not: see the note at the top of this
// file. The proposal is a value so the screen can show it and the reader can refuse it.
class BottleProposal {
  const BottleProposal({required this.sku, required this.millilitres});

  final String sku;
  final int millilitres;
}
