import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/recipe_collection.dart';
import '../domain/model/recipe.dart';
import '../domain/model/recipe_collections.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'theme.dart';

/// Makes or changes a collection of the reader's own.
///
/// **The screen ④ was for.** The recipes page shows *derived* folders -- made from the drinks themselves -- and a
/// collection is the reader saying "these belong together" in a way no derivation can guess. Until now the model and
/// its event family existed and nothing used them: a grep for `RecipeCollections` outside its own file found a single
/// comment.
///
/// **The same sheet shape as 记一瓶 and 写一条配方**, which is the pattern this application has settled on: one form
/// for one kind of writing, opened from the page whose subject it is.
///
/// **The membership is chosen from what exists rather than typed.** A collection holds recipes, other collections,
/// and derived folders, and all three are already on the screen behind the sheet -- so the list here is checkboxes
/// over names the reader recognises, not three text fields where a mistyped id would silently drop a member.
///
/// [editing] carries the collection being changed, so a change keeps its id and the fold replaces the record rather
/// than accumulating a second one.
Future<void> showCollectionEditor(
  BuildContext context, {
  required List<Recipe> recipes,
  required String Function(Recipe) nameOf,
  required RecipeCollections existing,
  RecipeCollection? editing,
  /// **What is already ticked, for a collection made out of a selection.**
  ///
  /// The owner asked that the bigger collection be customisable, and this is where "合并" lands: the reader ticks
  /// recipes and collections on the page, presses 收成一个合集, and arrives here with all of them chosen -- free to
  /// rename, untick, or add more. **The alternative, writing a record straight from the bar, would produce a
  /// collection named after a count**, which is the kind of name nobody chose.
  Set<String>? preselected,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // **The framework's own switch, and the reason two earlier attempts changed nothing**: a modal bottom sheet
  // *removes* the top padding from the MediaQuery it passes down, so reading `MediaQuery.paddingOf` inside one
  // reports zero -- and both a manual `system.top` and a `SafeArea` were reading a value that had deliberately
  // been emptied. `useSafeArea` hands it back.
  useSafeArea: true,
  backgroundColor: HollowPalette.surface,
  builder: (_) => _CollectionEditor(
    recipes: recipes,
    nameOf: nameOf,
    existing: existing,
    editing: editing,
    preselected: preselected,
  ),
);

class _CollectionEditor extends ConsumerStatefulWidget {
  const _CollectionEditor({
    required this.recipes,
    required this.nameOf,
    required this.existing,
    this.editing,
    this.preselected,
  });

  final List<Recipe> recipes;
  final String Function(Recipe) nameOf;
  final RecipeCollections existing;
  final RecipeCollection? editing;
  final Set<String>? preselected;

  @override
  ConsumerState<_CollectionEditor> createState() => _CollectionEditorState();
}

class _CollectionEditorState extends ConsumerState<_CollectionEditor> {
  late final TextEditingController _name;
  late Set<String> _chosen;
  String? _problem;

  /// The id being written.
  ///
  /// **Minted once, at open, and kept.** A change has to replace the record it came from, so the id may not move
  /// between the moment the sheet opens and the moment save is pressed -- and deriving it at save from a name the
  /// reader may have edited would make a rename produce a second collection.
  late final String _id;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    _id = editing?.id ?? 'own.collection.${DateTime.now().microsecondsSinceEpoch}';
    _name = TextEditingController(text: editing?.name ?? '');
    // **The selection when there is one, and the record's own members otherwise.** A preselected set is the whole
    // membership rather than an addition to it, which is what makes the bar's action "collect these" rather than
    // "add these to whatever was there".
    _chosen = widget.preselected != null
        ? {...widget.preselected!}
        : {
            for (final member in editing?.members ?? const <CollectionMember>[])
              member.encode(),
          };
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Everything that may be a member, as encoded members with the label to show.
  ///
  /// **Three kinds, and the ids are the wire form**, so what is ticked here is exactly what the event will carry --
  /// no translation step that could disagree with the fold.
  List<(String encoded, String label, bool isFolder)> get _choices => [
    for (final collection in widget.existing.collections.values)
      if (collection.id != _id)
        ('c:${collection.id}', collection.name, false),
    for (final recipe in widget.recipes)
      ('r:${recipe.id}', widget.nameOf(recipe), false),
  ];

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _problem = ref.copy(Copy.collectionNeedsName));
      return;
    }
    final members = <CollectionMember>[
      for (final encoded in _chosen)
        if (CollectionMember.tryDecode(encoded) case final member?) member,
    ];
    final notifier = ref.read(cellarProvider.notifier);
    notifier
        .setCollection(id: _id, name: name, members: members)
        .then((problem) {
      if (!mounted) return;
      if (problem == null) {
        Navigator.of(context).pop();
        return;
      }
      // **The refusal comes back as a sentence rather than as a stack overflow.** `checkMembership` catches a
      // collection that would contain itself before the event is written, because afterwards it would be in the
      // log and in every synced copy of it.
      setState(() => _problem = switch (problem) {
        CollectionWouldContainItself() => ref.copy(Copy.collectionWouldContainItself),
        CollectionUnnamed() => ref.copy(Copy.collectionNeedsName),
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Both insets, and the second one was missing the first time this pattern was written: `viewInsets` is the
    // keyboard and `padding` is the system's own bars, and clearing only the keyboard put the save button
    // underneath the navigation bar on a real handset.
    final insets = MediaQuery.viewInsetsOf(context);
    final system = MediaQuery.paddingOf(context);
    final choices = _choices;
    return SafeArea(
      top: true,
      bottom: false,
      child: Padding(
      // **Both insets on both ends.** The bottom was fixed first -- clearing only the keyboard left the save
      // button under the navigation bar -- and **the top was still hard-coded at 20**, which a screenshot from a
      // handset showed as the sheet's title running into the status bar. A modal sheet draws over everything,
      // so it has to clear the system's bars itself rather than relying on the page underneath to have done it.
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
            DualCopyText(Copy.collectionOwnTitle, style: HollowType.heading),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('collection-name'),
              controller: _name,
              decoration: InputDecoration(labelText: ref.copy(Copy.collectionFieldName)),
            ),
            const SizedBox(height: 18),
            DualCopyText(Copy.collectionFieldMembers, style: HollowType.caption),
            const SizedBox(height: 4),
            Text(ref.copy(Copy.collectionMembersHint), style: HollowType.caption),
            const SizedBox(height: 6),
            for (final (encoded, label, _) in choices)
              CheckboxListTile(
                key: ValueKey('collection-member-$encoded'),
                value: _chosen.contains(encoded),
                onChanged: (on) => setState(() {
                  if (on ?? false) {
                    _chosen.add(encoded);
                  } else {
                    _chosen.remove(encoded);
                  }
                }),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(label, style: HollowType.body),
              ),
            if (_problem case final problem?) ...[
              const SizedBox(height: 12),
              Text(problem, style: HollowType.caption.copyWith(color: HollowPalette.rose)),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('collection-save'),
                onPressed: _save,
                child: Text(ref.copy(Copy.collectionSave)),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
