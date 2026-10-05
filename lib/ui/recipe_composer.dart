import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/recipe_authoring.dart';
import '../domain/model/ingredient.dart';
import '../domain/units/measure_set.dart';
import '../domain/units/unit.dart';
import '../domain/units/unit_system.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'preferences_providers.dart';
import 'theme.dart';

/// Writes a recipe of the reader's own.
///
/// **The screen `docs/proposal-recipes-and-packs.md` §2 asked for**, and the one the application was missing
/// entirely: until now it had exactly two write paths, a bottle and a journal entry, and the proposal states the
/// gap in its own words -- *"Can a user create one? **No.**"*
///
/// **The same sheet shape as 记一瓶**, which is the proposal's instruction rather than a coincidence: one form for
/// one kind of writing, opened from the page whose subject it is. What is deliberately *not* the same is the
/// validation -- a bottle is a fact about a thing that exists, and a recipe is a composition somebody is inventing,
/// so the method is free text rather than a list and the glass is offered rather than required.
///
/// [editing] carries the recipe being changed, so an edit keeps its id and the fold replaces the record rather than
/// accumulating a second one. A new recipe gets an id from [RecipeAuthoredId.from], which is derived from the name
/// and a clock reading rather than random -- two devices that saw the same edit agree on what to call it.
Future<void> showRecipeComposer(
  BuildContext context, {
  required List<Ingredient> ingredients,
  AuthoredRecipe? editing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: HollowPalette.surface,
  builder: (_) => _RecipeComposer(ingredients: ingredients, editing: editing),
);

class _RecipeComposer extends ConsumerStatefulWidget {
  const _RecipeComposer({required this.ingredients, this.editing});

  final List<Ingredient> ingredients;
  final AuthoredRecipe? editing;

  @override
  ConsumerState<_RecipeComposer> createState() => _RecipeComposerState();
}

/// One line being composed.
///
/// **Mutable and owned by the sheet**, unlike everything in the domain layer: a half-typed line is not a record and
/// has no business being one. It becomes an [AuthoredItem] on save and nothing before that.
class _DraftLine {
  _DraftLine({String? ingredient, String? amount, this.unit, String? note})
    : ingredient = ingredient ?? '',
      amount = TextEditingController(text: amount ?? ''),
      note = TextEditingController(text: note ?? '');

  String ingredient;
  final TextEditingController amount;
  final TextEditingController note;
  Unit? unit;

  String get noteText => note.text.trim();

  /// Whether this line has anything in it at all.
  ///
  /// **Blank lines are dropped rather than refused.** A reader who pressed 加一行 and changed their mind should not
  /// have to find the line and remove it, and a form that refused would make them.
  bool get isEmpty => ingredient.isEmpty && amount.text.trim().isEmpty;

  void dispose() {
    amount.dispose();
    note.dispose();
  }
}

class _RecipeComposerState extends ConsumerState<_RecipeComposer> {
  late final TextEditingController _name;
  late final TextEditingController _method;
  late final List<_DraftLine> _lines;
  String? _problem;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _name = TextEditingController(text: editing?.name ?? '');
    _method = TextEditingController(text: editing?.method ?? '');
    _lines = [
      for (final item in editing?.items ?? const <AuthoredItem>[])
        _DraftLine(
          ingredient: item.ingredientId,
          amount: item.amount,
          unit: _unitNamed(item.unit),
          note: item.note,
        ),
    ];
    // One empty line to start, so the form shows what a line looks like rather than only the button that adds one.
    //
    // **Its unit is the cellar's primary measure rather than nothing.** A picker showing nothing makes the reader
    // open it just to find out what is on offer, and the answer to "what do I measure in" is already known -- it is
    // the same default the shelf beside this form displays. A line saved without touching the menu is therefore
    // saved in millilitres, which is what it looked like it was in.
    if (_lines.isEmpty) _lines.add(_DraftLine(unit: _units.first));
  }

  @override
  void dispose() {
    _name.dispose();
    _method.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  /// The unit a stored line names, or null when this build does not carry it.
  ///
  /// **Null rather than a guess.** A recipe written by a build with a unit this one has never heard of keeps its
  /// text in the field and shows no unit chosen; inventing the nearest one would silently rewrite somebody's record.
  Unit? _unitNamed(String? name) {
    if (name == null || name.isEmpty) return null;
    // **Matched on the id, which is the stable machine name.** `Unit` is a class rather than an enum, so there is
    // no `values` to walk: the list of units this cellar offers comes from the preferences, and the id is what a
    // stored line names.
    for (final unit in _allUnits) {
      if (unit.id == name) return unit;
    }
    return null;
  }

  /// The units this cellar measures liquids in, primary first.
  ///
  /// The same resolution `_AddBottleSheet` uses, so a recipe and the shelf it is judged against cannot disagree
  /// about what an unconfigured cellar measures in.
  List<Unit> get _units {
    // **Read straight, not through `.value`**: the preferences provider is a plain notifier, so what it hands
    // back is the value. Reaching for `.value` on it was the first version of this line and it does not compile,
    // which is the compiler doing its job.
    final preferences = ref.watch(preferencesProvider);
    return preferences.measuresFor(MatterState.liquid)?.all ?? const <Unit>[UnitSystem.millilitre];
  }

  /// Every unit the application knows, for looking a stored name up in.
  ///
  /// A stored line names a unit by its id, and resolving it has to work for a recipe written while this cellar was
  /// set to a different measuring system -- so the lookup is over the whole catalogue rather than over the reader's
  /// current set.
  static List<Unit> get _allUnits => UnitSystem.all;

  /// Everything the reader may name, in the order the picker offers it.
  List<Ingredient> get _choices {
    final sorted = [...widget.ingredients]..sort((a, b) => a.name.compareTo(b.name));
    return sorted;
  }

  /// Whether every ingredient the draft names is one this build can resolve.
  ///
  /// **Checked on save rather than as the reader types**, because a partially typed identifier matches nothing and
  /// a form that complained mid-word would be complaining about the state of a word.
  bool _knowsEverything() => _knownIds.containsAll(
    _lines.where((l) => !l.isEmpty).map((l) => l.ingredient),
  );

  /// Whether any line says how much without saying what.
  ///
  /// **The gap a UI test found on 2026-10-01.** The draft drops a line that is entirely blank, and blank was
  /// "no ingredient *and* no amount" -- so somebody who typed `30` and never chose what it was thirty of produced a
  /// line that survived, and a recipe whose ingredient id was the empty string. The check mirrors
  /// `RecipeLineWithoutIngredient` so the form refuses it with a sentence rather than the store refusing it silently.
  bool _everyLineNamesSomething() =>
      _lines.every((l) => l.isEmpty || l.ingredient.isNotEmpty);

  Set<String> get _knownIds => {for (final i in widget.ingredients) i.id};

  void _save() {
    final name = _name.text.trim();
    final lines = [
      for (final line in _lines)
        if (!line.isEmpty)
          AuthoredItem(
            ingredientId: line.ingredient,
            amount: line.amount.text.trim(),
            unit: line.unit?.id,
            note: line.noteText.isEmpty ? null : line.noteText,
          ),
    ];

    // **Every problem is reported at once rather than one per attempt**, which is the shape `validateAuthored`
    // returns and the reason it returns a list: making somebody press save twice to learn two things is a form
    // wasting their time on purpose.
    if (name.isEmpty || lines.isEmpty) {
      setState(() => _problem = ref.copy(Copy.recipeNeedsNameAndLine));
      return;
    }
    if (!_everyLineNamesSomething()) {
      setState(() => _problem = ref.copy(Copy.recipeLineNeedsIngredient));
      return;
    }
    if (!_knowsEverything()) {
      setState(() => _problem = ref.copy(Copy.recipeUnknownIngredient));
      return;
    }

    final method = _method.text.trim();
    final editing = widget.editing;
    final recipe = AuthoredRecipe(
      // **An edit carries its own id and a new recipe carries a placeholder.** The real id is minted by the notifier
      // from the log's own clock -- see `authorRecipe` -- because taking a reading is the log's business rather than
      // a widget's, and the `id:` passed with `editing` is what makes an edit replace a record instead of adding a
      // second one beside it.
      id: editing?.id ?? '',
      name: name,
      items: lines,
      folder: editing?.folder,
      subtitle: editing?.subtitle,
      description: editing?.description,
      method: method.isEmpty ? null : method,
      glass: editing?.glass,
      ice: editing?.ice,
      garnish: editing?.garnish,
    );
    ref.read(cellarProvider.notifier).authorRecipe(recipe, id: editing?.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // **Both insets, and the second one was missing in the first version.** `viewInsets` is the keyboard;
    // `padding` is the system's own bars. Clearing only the keyboard left the save button underneath the
    // navigation bar, on a handset, with no way to reach it -- which a screenshot caught and no test could have.
    // `_AddBottleSheet` has carried both since it was written, and this is the same arrangement.
    final insets = MediaQuery.viewInsetsOf(context);
    final system = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + insets.bottom + system.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DualCopyText(Copy.recipeOwnTitle, style: HollowType.heading),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('recipe-name'),
              controller: _name,
              decoration: InputDecoration(labelText: ref.copy(Copy.recipeFieldName)),
            ),
            const SizedBox(height: 18),
            DualCopyText(Copy.recipeFieldIngredients, style: HollowType.caption),
            const SizedBox(height: 8),
            for (var i = 0; i < _lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _LineRow(
                  index: i,
                  line: _lines[i],
                  choices: _choices,
                  units: _units,
                  ingredientLabel: ref.copy(Copy.recipeFieldIngredients),
                  onChanged: () => setState(() {}),
                  onRemove: _lines.length == 1
                      // The last line is cleared rather than removed, so the form never becomes a name with nothing
                      // under it and no way to add anything back except the button.
                      ? () => setState(() {
                          _lines[i].dispose();
                          _lines[i] = _DraftLine();
                        })
                      : () => setState(() {
                          _lines.removeAt(i).dispose();
                        }),
                ),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _lines.add(_DraftLine(unit: _units.first))),
              icon: const Icon(Icons.add, size: 18),
              label: Text(ref.copy(Copy.recipeAddLine)),
            ),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('recipe-method'),
              controller: _method,
              maxLines: 3,
              minLines: 1,
              decoration: InputDecoration(
                labelText: ref.copy(Copy.recipeFieldMethod),
                hintText: ref.copy(Copy.recipeMethodHint),
              ),
            ),
            if (_problem case final problem?) ...[
              const SizedBox(height: 12),
              Text(
                problem,
                style: HollowType.caption.copyWith(color: HollowPalette.rose),
              ),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('recipe-save'),
                onPressed: _save,
                child: Text(ref.copy(Copy.recipeSave)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One ingredient line: what, how much, in what, and an optional note.
///
/// **The amount-and-unit pair follows `AmountRow`'s shape** -- a number box beside a unit menu inside a decorator,
/// for the reasons that widget records at length: the caller owns the chosen value, and a `DropdownButtonFormField`
/// would fight that. What is *not* reused is `AmountRow` itself, because its number box is a numeric keyboard and
/// the identifier beside it here is a word.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.index,
    required this.line,
    required this.choices,
    required this.units,
    required this.ingredientLabel,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _DraftLine line;
  final List<Ingredient> choices;
  final List<Unit> units;

  /// What the picker is for, resolved by the sheet -- a `StatelessWidget` has no `ref` to read copy with.
  final String ingredientLabel;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // **A value the menu was not offered cannot be displayed by a `DropdownButton`**, so a line whose ingredient
    // this build does not carry -- one written by a newer build, say -- keeps its text and shows nothing chosen
    // rather than throwing or silently picking the first item.
    final chosen = choices.where((i) => i.id == line.ingredient).firstOrNull;
    final unit = units.contains(line.unit) ? line.unit : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // **No floating label here, because the section heading above already says 原料.** The first version
              // passed an empty label and the field read as a bare dash with nothing to explain it; the second put
              // the section's own word inside a field inside that section, which a screenshot showed repeating
              // itself. What identifies the field is its *hint* -- an em dash when nothing is chosen -- and the
              // heading it sits under.
              child: InputDecorator(
                decoration: const InputDecoration(labelText: ''),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Ingredient>(
                    key: ValueKey('recipe-line-$index-ingredient'),
                    isExpanded: true,
                    isDense: true,
                    hint: Text(line.ingredient.isEmpty ? '—' : line.ingredient),
                    value: chosen,
                    dropdownColor: HollowPalette.surfaceRaised,
                    style: HollowType.body,
                    items: [
                      for (final ingredient in choices)
                        DropdownMenuItem(
                          value: ingredient,
                          child: Text(ingredient.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (ingredient) {
                      if (ingredient == null) return;
                      line.ingredient = ingredient.id;
                      onChanged();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: TextField(
                key: ValueKey('recipe-line-$index-amount'),
                controller: line.amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(labelText: ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(
              width: 108,
              child: InputDecorator(
                // **The unit's own name when nothing is chosen.** A blank box beside a blank box says nothing about
                // which is which; this one shows the cellar's default, which is also what a line will be saved in.
                decoration: InputDecoration(labelText: unit == null ? units.first.symbol : ''),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Unit>(
                    key: ValueKey('recipe-line-$index-unit'),
                    isExpanded: true,
                    isDense: true,
                    value: unit,
                    dropdownColor: HollowPalette.surfaceRaised,
                    style: HollowType.numeric,
                    items: [
                      for (final option in units)
                        DropdownMenuItem(value: option, child: Text(option.symbol)),
                    ],
                    onChanged: (option) {
                      line.unit = option;
                      onChanged();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                key: ValueKey('recipe-line-$index-note'),
                controller: line.note,
                decoration: const InputDecoration(labelText: ''),
              ),
            ),
            IconButton(
              key: ValueKey('recipe-line-$index-remove'),
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 18),
              color: HollowPalette.inkFaint,
            ),
          ],
        ),
      ],
    );
  }
}
