import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/court_pack.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'theme.dart';

/// Renames, describes, recolours or reorders a folder.
///
/// **`docs/proposal-recipes-and-packs.md` section 1's last bullet**: the user can create, rename, describe, recolour,
/// reorder and delete a pack, and deleting one asks what happens to its recipes rather than silently orphaning them.
/// The fold, the write path and the read path landed first; this is the screen those three were for.
///
/// **A pack is where a recipe came from, so this edits the folder itself** -- not the recipes in it. The recipes keep
/// their own packId and are untouched by a rename, which is what makes renaming a folder something a reader can do
/// without worrying about what is inside it.
///
/// [key] is the folder's key, which is what a pack's id is; [existing] is the pack already defining it, when there is
/// one. **Opening this on a folder nobody has named yet is how a pack is created**, which is why there is no separate
/// "new folder" flow: a reader renames a derived folder and it becomes theirs.
Future<void> showPackEditor(
  BuildContext context, {
  required String packKey,
  required String derivedLabel,
  CourtPack? existing,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: HollowPalette.surface,
  builder: (_) => _PackEditor(packKey: packKey, derivedLabel: derivedLabel, existing: existing),
);

class _PackEditor extends ConsumerStatefulWidget {
  const _PackEditor({required this.packKey, required this.derivedLabel, this.existing});

  final String packKey;
  final String derivedLabel;
  final CourtPack? existing;

  @override
  ConsumerState<_PackEditor> createState() => _PackEditorState();
}

class _PackEditorState extends ConsumerState<_PackEditor> {
  late final TextEditingController _name;
  late final TextEditingController _note;
  late final TextEditingController _accent;
  late final TextEditingController _order;
  String? _problem;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    // **The derived label is what the field starts with**, so opening the sheet on an unnamed folder shows the name
    // the reader is already looking at rather than an empty box -- and saving without typing keeps it, which is what
    // makes this a rename rather than a way to end up with a nameless folder.
    _name = TextEditingController(text: existing?.name ?? widget.derivedLabel);
    _note = TextEditingController(text: existing?.note ?? '');
    _accent = TextEditingController(text: existing?.accent ?? '');
    _order = TextEditingController(text: existing?.order?.toString() ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _accent.dispose();
    _order.dispose();
    super.dispose();
  }

  /// A colour of the form #RRGGBB, or null when the field is empty, or the empty string when it is malformed.
  ///
  /// **Refused rather than silently falling back to gold**, which is what the recipes page does when *drawing* an
  /// unparsable accent. The two are different jobs and both are needed: drawing has to survive bad data, and a form
  /// is where bad data is caught. A reader who typed 8A5A32 without the hash would otherwise save something that
  /// looked right and drew as gold.
  String? get _accentValue {
    final text = _accent.text.trim();
    if (text.isEmpty) return null;
    final body = text.startsWith('#') ? text.substring(1) : text;
    if (body.length != 6 || int.tryParse(body, radix: 16) == null) return '';
    return '#${body.toUpperCase()}';
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _problem = ref.copy(Copy.packNeedsName));
      return;
    }
    final accent = _accentValue;
    if (accent == '') {
      setState(() => _problem = ref.copy(Copy.packAccentNotAColour));
      return;
    }
    final note = _note.text.trim();
    ref.read(cellarProvider.notifier).definePack(
      CourtPack(
        id: widget.packKey,
        name: name,
        note: note.isEmpty ? null : note,
        accent: accent,
        order: int.tryParse(_order.text.trim()),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    await ref.read(cellarProvider.notifier).removePack(widget.packKey);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // **Both insets on both ends.** viewInsets is the keyboard and padding is the system's bars; the bottom is what
    // fixed the save button being under the navigation bar, and **the top is still open** -- two attempts to clear
    // the status bar changed nothing because MediaQuery.padding reports zero inside these sheets. This sheet uses the
    // same arrangement as its two neighbours so that when the cause is found, it is fixed once rather than thrice.
    final insets = MediaQuery.viewInsetsOf(context);
    final system = MediaQuery.paddingOf(context);
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
            DualCopyText(Copy.packOwnTitle, style: HollowType.heading),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey('pack-name'),
              controller: _name,
              decoration: InputDecoration(labelText: ref.copy(Copy.packFieldName)),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('pack-note'),
              controller: _note,
              decoration: InputDecoration(
                labelText: ref.copy(Copy.packFieldNote),
                hintText: ref.copy(Copy.packNoteHint),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('pack-accent'),
                    controller: _accent,
                    decoration: InputDecoration(
                      labelText: ref.copy(Copy.packFieldAccent),
                      hintText: ref.copy(Copy.packAccentHint),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: const ValueKey('pack-order'),
                    controller: _order,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: ref.copy(Copy.packFieldOrder)),
                  ),
                ),
              ],
            ),
            if (_problem case final problem?) ...[
              const SizedBox(height: 12),
              Text(problem, style: HollowType.caption.copyWith(color: HollowPalette.rose)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                // **Only for a folder the reader made.** The shipped pack cannot be removed -- CourtPackEvents.removed
                // refuses its id -- so offering the button for it would be offering one that cannot work.
                if (widget.existing != null && !widget.existing!.isBuiltIn)
                  TextButton(
                    key: const ValueKey('pack-delete'),
                    onPressed: _remove,
                    child: Text(
                      ref.copy(Copy.packDelete),
                      style: HollowType.caption.copyWith(color: HollowPalette.rose),
                    ),
                  ),
                const Spacer(),
                FilledButton(
                  key: const ValueKey('pack-save'),
                  onPressed: _save,
                  child: Text(ref.copy(Copy.packSave)),
                ),
              ],
            ),
            // **What happens to the recipes, said before anybody presses the button** -- the proposal asks that
            // deleting a pack asks what happens to its recipes rather than silently orphaning them, and a sentence
            // beside the button is the asking. The recipes genuinely do stay: a pack is a field on a recipe, so
            // removing the folder leaves them with a packId nothing defines, which is what "belongs to no folder"
            // means and is the state every shipped recipe was in before packs existed.
            if (widget.existing != null && !widget.existing!.isBuiltIn) ...[
              const SizedBox(height: 6),
              Text(ref.copy(Copy.packDeleteKeepsRecipes), style: HollowType.caption),
            ],
          ],
        ),
      ),
    );
  }
}
