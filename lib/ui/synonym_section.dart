import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/overlay/overlay_key.dart';
import '../domain/overlay/synonyms.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'theme.dart';

/// **The reader's dictionary of equivalent names, edited in bulk.**
///
/// The owner asked for this in the 记录 tab, with the problem stated as examples: 利口酒/力娇/力娇酒,
/// 安高天娜/安哥斯图拉, 马天尼/马提尼, 菲士/菲兹, 金酒/琴酒, 蓝柑/蓝橙. `lib/domain/overlay/synonyms.dart`
/// holds the grammar and the lookup; this is the screen, and it is a **text block rather than a form** because
/// that is what "批量" means: somebody with twenty names pastes twenty lines, rather than filling in twenty
/// rows one at a time.
///
/// **What it shows before it saves**, and each of these is a decision rather than decoration:
///
/// * the lines it understood, counted -- so "did it take?" is answerable without leaving the screen;
/// * **the lines it did not, with their numbers** -- a bulk editor that silently drops one of twenty names
///   surfaces weeks later as a drink that cannot be made, which is the failure this whole feature exists to
///   prevent;
/// * and the reader's current vocabulary as it stands after the edit, so the dictionary is visible rather
///   than trusted.
class SynonymSection extends ConsumerStatefulWidget {
  const SynonymSection({super.key});

  @override
  ConsumerState<SynonymSection> createState() => _SynonymSectionState();
}

class _SynonymSectionState extends ConsumerState<SynonymSection> {
  final _block = TextEditingController();

  /// Set once, from what is stored, and never overwritten afterwards: a screen that reloaded the stored text
  /// on every rebuild would wipe out what somebody was in the middle of typing.
  bool _seeded = false;

  @override
  void dispose() {
    _block.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cellar = ref.watch(cellarProvider).value;
    final stored = cellar?.overlay.synonymBlock ?? '';

    if (!_seeded && cellar != null) {
      _block.text = stored;
      _seeded = true;
    }

    final parsed = parseSynonymBlock(_block.text);
    final dirty = _block.text.trim() != stored.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.synonymTitle, style: HollowType.title),
        const SizedBox(height: 6),
        DualCopyText(Copy.synonymNote, style: HollowType.caption),
        const SizedBox(height: 6),
        DualCopyText(Copy.synonymExample, style: HollowType.caption),
        const SizedBox(height: 14),

        TextField(
          key: const ValueKey('synonym-block'),
          controller: _block,
          maxLines: 8,
          minLines: 4,
          style: HollowType.body,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          // Every keystroke re-reads the block, which is a split over a handful of lines -- and it is what
          // lets the screen say what it understood *before* anything is saved.
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 10),

        // What the parser made of it. Counted and named, rather than a tick.
        _Line(
          label: Copy.synonymUnderstood,
          value: '${parsed.groups.length}',
        ),
        if (parsed.problems.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final problem in parsed.problems)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                // The number is the reader's own line number, which is why the parser counts from one.
                '${ref.copy(Copy.synonymLineProblem)} ${problem.line}: ${problem.reason} '
                '— "${problem.text}"',
                style: HollowType.caption.copyWith(color: HollowPalette.rose),
              ),
            ),
        ],
        const SizedBox(height: 10),

        Row(
          children: [
            FilledButton(
              key: const ValueKey('synonym-apply'),
              onPressed: !dirty || !parsed.ok
                  ? null
                  : () => ref
                        .read(cellarProvider.notifier)
                        .editOverlay(OverlayKey.synonymTable, _block.text),
              child: DualCopyText(Copy.synonymApply, style: HollowType.body),
            ),
            const SizedBox(width: 12),
            // **Disabled for the same reason the save is, and the reason is the point**: saving a block with a
            // line the parser could not read would store the good lines and lose the bad one silently.
            if (!parsed.ok)
              Expanded(
                child: DualCopyText(
                  Copy.synonymFixFirst,
                  style: HollowType.caption.copyWith(color: HollowPalette.rose),
                ),
              )
            else if (!dirty)
              Expanded(
                child: DualCopyText(Copy.synonymUnchanged, style: HollowType.caption),
              ),
          ],
        ),

        if (stored.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          DualCopyText(Copy.synonymInForce, style: HollowType.caption),
          const SizedBox(height: 6),
          for (final group in parseSynonymBlock(stored).groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(group.toString(), style: HollowType.body),
            ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final CopyLine label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: DualCopyText(label, style: HollowType.caption)),
      Text(value, style: HollowType.body),
    ],
  );
}
