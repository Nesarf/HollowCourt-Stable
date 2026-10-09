import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/archival_service.dart';
import 'archive_providers.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'theme.dart';

/// **The reader's archives: what can be moved, and which packages are read.**
///
/// `docs/archival.md`, and the two halves are the owner's decisions of 2026-10-08:
///
/// * **Compaction here is a move rather than a deletion.** The button says what will be moved -- *"$count events, up to
///   $through"* -- rather than saying "archive now", because a reader who is about to create a file they will have to
///   look after is entitled to know what goes in it.
/// * **No package is read unless it was chosen**, with select-all and invert. That is what makes the consequences safe:
///   **a package the reader deletes is simply not in the list**, so nothing has to notice and no history changes
///   behind their back.
///
/// **The grain is five years and the section says so**, because a reader should be able to predict what the button
/// does without pressing it.
class ArchiveSection extends ConsumerWidget {
  const ArchiveSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(archiveCatalogProvider);
    final selected = ref.watch(archiveSelectionProvider);
    final cellar = ref.watch(cellarProvider).value;

    final entries = catalog.value ?? const <ArchiveEntry>[];
    final usable = [for (final entry in entries) if (entry.isUsable) entry.fileName];
    final attachedEvents = [
      for (final entry in entries)
        if (entry.isUsable && selected.contains(entry.fileName)) entry.count ?? 0,
    ].fold<int>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.archiveHeading, style: HollowType.heading),
        const SizedBox(height: 6),
        DualCopyText(Copy.archiveExplain, style: HollowType.caption),

        // ---- what can be moved ----
        const SizedBox(height: 14),
        if (cellar == null)
          const SizedBox.shrink()
        else
          _MoveButton(cellar: cellar),

        // ---- which packages are read ----
        const SizedBox(height: 18),
        DualCopyText(Copy.archiveWhich, style: HollowType.title),
        const SizedBox(height: 6),
        if (entries.isEmpty)
          Text(ref.copy(Copy.archiveNone), style: HollowType.caption)
        else ...[
          Wrap(
            spacing: 8,
            children: [
              // **The two the owner asked for by name.** A reader with twenty packages who wants all but one should
              // not have to tick nineteen, and one who wants none should not have to untick twenty.
              OutlinedButton(
                key: const ValueKey('archive-select-all'),
                onPressed: () =>
                    ref.read(archiveSelectionProvider.notifier).selectAll(usable),
                child: Text(ref.copy(Copy.archiveSelectAll)),
              ),
              OutlinedButton(
                key: const ValueKey('archive-invert'),
                onPressed: () => ref.read(archiveSelectionProvider.notifier).invert(usable),
                child: Text(ref.copy(Copy.archiveInvert)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final entry in entries)
            CheckboxListTile(
              key: ValueKey('archive-${entry.fileName}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              // **An unreadable package is shown and cannot be attached.** The alternative -- hiding it -- leaves a file
              // the reader can see in their own directory and not here, with nothing to explain the difference; and
              // the alternative to *that*, attaching it anyway, would put nothing into the history while looking like
              // it had.
              value: entry.isUsable && selected.contains(entry.fileName),
              onChanged: entry.isUsable
                  ? (_) =>
                      ref.read(archiveSelectionProvider.notifier).toggle(entry.fileName)
                  : null,
              title: Text(entry.fileName, style: HollowType.body),
              subtitle: Text(
                entry.problem != null
                    ? Copy.archiveUnusable(entry.problem!)
                    : '${entry.count}  ·  ${entry.package!.manifest.firstClock} → '
                        '${entry.package!.manifest.lastClock}',
                style: HollowType.caption,
              ),
            ),
          if (selected.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(Copy.archiveAttached(selected.length, attachedEvents), style: HollowType.caption),
          ],
        ],
      ],
    );
  }
}

/// The button that moves a range into a package, and it says what it will move.
class _MoveButton extends ConsumerStatefulWidget {
  const _MoveButton({required this.cellar});

  final Cellar cellar;

  @override
  ConsumerState<_MoveButton> createState() => _MoveButtonState();
}

class _MoveButtonState extends ConsumerState<_MoveButton> {
  ArchiveProposal? _proposal;
  bool _looked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _look();
  }

  /// Asks the service what it would take, **without taking it.**
  ///
  /// A dry run, and it is why the button can say what will happen: a reader being asked to accept a file they will have
  /// to look after should see *"N events, up to X"* before the file exists rather than after.
  Future<void> _look() async {
    final directory = await ref.read(archivesDirectoryProvider.future);
    final proposal = await ArchivalService(
      log: widget.cellar.log,
      packagesDirectory: directory,
    ).propose(nowMillis: DateTime.now().millisecondsSinceEpoch);
    if (!mounted) return;
    setState(() {
      _proposal = proposal;
      _looked = true;
    });
  }

  Future<void> _move() async {
    setState(() => _busy = true);
    final directory = await ref.read(archivesDirectoryProvider.future);
    await ArchivalService(
      log: widget.cellar.log,
      packagesDirectory: directory,
    ).archive(
      nowMillis: DateTime.now().millisecondsSinceEpoch,
      nodeId: widget.cellar.log.clock.nodeId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    // The list has to be re-read: a package that was just written is not in the catalog the screen is holding.
    ref.invalidate(archiveCatalogProvider);
    await _look();
  }

  @override
  Widget build(BuildContext context) {
    if (!_looked) return const SizedBox.shrink();
    final proposal = _proposal;
    if (proposal == null) {
      return Text(ref.copy(Copy.archiveNothingOld), style: HollowType.caption);
    }
    return FilledButton.tonal(
      key: const ValueKey('archive-move'),
      onPressed: _busy ? null : _move,
      child: Text(
        Copy.archiveMovePrompt(proposal.count, proposal.throughClock),
        style: HollowType.caption,
      ),
    );
  }
}
