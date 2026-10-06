import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/ingredient_authoring.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'theme.dart';

/// Adds or changes an ingredient of the reader's own.
///
/// **Stage ③'s screen.** `authorIngredient` and `removeAuthoredIngredient` have been on the notifier since the
/// authored-ingredient family landed, and **no screen called either of them** -- so a reader could not add the one
/// ingredient their own cellar is full of, which was the whole reason the family was built.
///
/// **Narrower than the domain model on purpose.** `Ingredient` carries alcohol by volume, sugar per litre, density,
/// bottle sizes and a source bucket; a person adding *"the plum wine my neighbour makes"* knows none of those, and a
/// form that asked would be asking them to guess numbers that section 5's arithmetic then uses. What is asked is what
/// somebody can state. The rest stays absent rather than defaulted, which is the rule the seed follows for the 142
/// ingredients whose category nobody recorded.
Future<void> showIngredientEditor(
  BuildContext context, {
  AuthorIngredientView? editing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: HollowPalette.surface,
  builder: (_) => _IngredientEditor(editing: editing),
);

/// What the editor needs to know about an existing ingredient, whether it came from the log or the library.
///
/// **A view rather than two code paths**, because the sheet's job is identical in both cases: show four fields, refuse
/// a blank name, write a record. What differs is only whether the delete button appears, and that is a field.
class AuthorIngredientView {
  const AuthorIngredientView({
    required this.id,
    required this.name,
    this.kind,
    this.aliases = const [],
    this.note,
    required this.isMine,
  });

  final String id;
  final String name;
  final String? kind;
  final List<String> aliases;
  final String? note;

  /// False for one the application ships, which cannot be changed or removed.
  final bool isMine;
}

class _IngredientEditor extends ConsumerStatefulWidget {
  const _IngredientEditor({this.editing});

  final AuthorIngredientView? editing;

  @override
  ConsumerState<_IngredientEditor> createState() => _IngredientEditorState();
}

class _IngredientEditorState extends ConsumerState<_IngredientEditor> {
  late final TextEditingController _name;
  late final TextEditingController _kind;
  late final TextEditingController _aliases;
  late final TextEditingController _note;
  String? _problem;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _name = TextEditingController(text: editing?.name ?? '');
    _kind = TextEditingController(text: editing?.kind ?? '');
    _aliases = TextEditingController(text: editing?.aliases.join(', ') ?? '');
    _note = TextEditingController(text: editing?.note ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _kind.dispose();
    _aliases.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _problem = ref.copy(Copy.ingredientNeedsName));
      return;
    }
    final kind = _kind.text.trim();
    final note = _note.text.trim();
    ref.read(cellarProvider.notifier).authorIngredient(
      AuthoredIngredient(
        // **The id is the editing one or a placeholder.** The notifier mints a real one from the name and the log's
        // clock when none is given, because taking a clock reading is the log's business rather than a widget's.
        id: widget.editing?.id ?? '',
        name: name,
        // **The kind is free text and stays a string**, which is the proposal's design: the kinds are data, so a
        // reader can add 茶 or 酊剂 the way they add a collection, and a closed enum would mean a build to add a shape.
        category: kind.isEmpty ? null : kind,
        // Split on commas and drop the blanks, so a trailing comma does not become an empty alias -- which would be
        // a name the ingredient answers to that is the empty string.
        aliases: [
          for (final part in _aliases.text.split(','))
            if (part.trim().isNotEmpty) part.trim(),
        ],
        note: note.isEmpty ? null : note,
      ),
      id: widget.editing?.isMine ?? false ? widget.editing!.id : null,
    );
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final editing = widget.editing;
    if (editing == null) return;
    await ref.read(cellarProvider.notifier).removeAuthoredIngredient(editing.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Both insets on both ends. The top half comes from `useSafeArea` on the `showModalBottomSheet` above rather
    // than from here, because `paddingOf(context).top` is zero inside a modal sheet by design.
    final insets = MediaQuery.viewInsetsOf(context);
    final system = MediaQuery.paddingOf(context);
    final editing = widget.editing;
    final removable = editing != null && editing.isMine;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 20 + insets.bottom + system.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DualCopyText(Copy.ingredientOwnTitle, style: HollowType.heading),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('ingredient-name'),
              controller: _name,
              decoration: InputDecoration(labelText: ref.copy(Copy.packFieldName)),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('ingredient-kind'),
              controller: _kind,
              decoration: InputDecoration(
                labelText: ref.copy(Copy.ingredientFieldKind),
                hintText: ref.copy(Copy.ingredientKindHint),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('ingredient-aliases'),
              controller: _aliases,
              decoration: InputDecoration(
                labelText: ref.copy(Copy.ingredientFieldAliases),
                hintText: ref.copy(Copy.ingredientAliasesHint),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('ingredient-note'),
              controller: _note,
              decoration: InputDecoration(labelText: ref.copy(Copy.packFieldNote)),
            ),
            if (_problem case final problem?) ...[
              const SizedBox(height: 12),
              Text(problem, style: HollowType.caption.copyWith(color: HollowPalette.rose)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                // **Only for one the reader added.** The library's ingredients are part of the build and
                // `IngredientAuthoredEvents.removed` refuses an id that is not `own.`-prefixed, so offering the
                // button for one would be offering one that cannot work.
                if (removable)
                  TextButton(
                    key: const ValueKey('ingredient-delete'),
                    onPressed: _remove,
                    child: Text(
                      ref.copy(Copy.ingredientDelete),
                      style: HollowType.caption.copyWith(color: HollowPalette.rose),
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('ingredient-save'),
                  onPressed: _save,
                  child: Text(ref.copy(Copy.ingredientSave)),
                ),
              ],
            ),
            // **Said before the button is pressed.** A recipe or a bottle may name this ingredient and those
            // references are not rewritten, so the reader is told what they will be left with rather than finding out
            // on the shelf.
            if (removable) ...[
              const SizedBox(height: 6),
              Text(ref.copy(Copy.ingredientDeleteKeepsReferences), style: HollowType.caption),
            ],
          ],
        ),
      ),
    );
  }
}
