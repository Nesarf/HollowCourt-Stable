import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'archive_providers.dart';
import 'l10n/copy_resolution.dart';
import 'library.dart';
import 'prism.dart';
import 'theme.dart';

/// **The line that says the readings below were folded from more than the working log.**
///
/// `docs/archival.md` sets the rule this exists to keep: **history depth is a visible choice rather than a hidden
/// constant.** The choosing half is `ArchiveSection` in 设置, where a reader ticks packages. **This is the other half,
/// and it was missing** -- attaching a package changes the value, the consumption curve, the statistics, the money
/// windows and the running-low speeds on the cellar page, and until now **nothing on that page said so.**
///
/// **`Cellar.archivedEvents` and `readsArchives` were written for exactly this and had no caller.** The design note
/// names the shape it was guarding against: *"a reader attaching archives and still seeing a truncated chart, which is
/// the silent-failure shape this project keeps meeting."* A reader seeing a chart that is **longer** than they expected
/// has met the same failure from the other side, and this is what tells them why.
///
/// **It renders nothing when no package is attached**, which is the ordinary case and the reason it can be put at the
/// top of a page without costing anything: a cellar whose history fits in its log looks exactly as it did before this
/// existed.
///
/// **Two numbers, from two places, and they are deliberately not the same kind of thing**: the package count is how
/// many the reader has ticked, and the event count is how many the fold **actually used** -- `Cellar.archivedEvents`,
/// counted as the merge happened. A ticked package that turned out to hold nothing contributes to the first and not
/// the second, and saying both is more honest than picking one.
class ArchivedHistoryNote extends ConsumerWidget {
  const ArchivedHistoryNote({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cellar = ref.watch(cellarProvider).value;
    // **`readsArchives` rather than the selection length**, because the question is what the readings were folded
    // from: a reader who has ticked a package that contributed no events has not changed anything, and a note claiming
    // otherwise would send them to 设置 to investigate a difference that is not there.
    if (cellar == null || !cellar.readsArchives) return const SizedBox.shrink();

    final packages = ref.watch(archiveSelectionProvider).length;
    final text = ref
        .copy(Copy.journalReadsArchives)
        .replaceFirst('{packages}', '$packages')
        .replaceFirst('{events}', '${cellar.archivedEvents}');

    return Padding(
      key: const ValueKey('cellar-reads-archives'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // **The same mark the page uses for a note about the numbers**, so this reads as a qualification of what
          // follows rather than as a heading of its own.
          const Prism(size: 14, facet: false),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: HollowType.caption,
              // The count is a number the reader may want to check against their own directory, so a long sentence
              // wraps rather than being cut. Nothing here is a fixed height.
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
