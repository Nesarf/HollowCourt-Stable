import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/event_store.dart';
import 'library.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'theme.dart';

/// Reads the whole log and says what is wrong with it, or that nothing is.
///
/// **The findings are the open report's, not a second opinion.** `EventLog.open` already parses every
/// line, recognises a torn tail, counts repeated clock readings and lists the lines it cannot read;
/// `StockLedger` already lists the operations that name a bottle nobody added and the bottles that
/// were added twice. This screen exists because all of that was **invisible** -- it was computed on
/// every launch and the only way to see it was to write a test. A diagnostic that re-counted for
/// itself would be a second answer to a question that already has one.
///
/// **Why a button rather than a live reading.** The report belongs to the moment the file was read.
/// A sync from another device, or a hand-edit, changes the file underneath a running application, and
/// the honest way to answer "is it still clean" is to read it again -- which is what the button does,
/// through the notifier's own `reload`, so the shelf and the report are re-folded from the same bytes
/// rather than from two different reads.
class IntegritySection extends ConsumerStatefulWidget {
  const IntegritySection({super.key});

  @override
  ConsumerState<IntegritySection> createState() => _IntegritySectionState();
}

class _IntegritySectionState extends ConsumerState<IntegritySection> {
  /// True while a re-read is in flight, so the button can say so instead of looking ignored.
  bool _checking = false;

  Future<void> _run() async {
    setState(() => _checking = true);
    try {
      await ref.read(cellarProvider.notifier).reload();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cellar = ref.watch(cellarProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.integrityHeading, style: HollowType.heading),
        const SizedBox(height: 10),
        DualCopyText(Copy.integrityExplain, style: HollowType.caption),
        const SizedBox(height: 12),
        if (cellar == null)
          DualCopyText(Copy.integrityNoLog, style: HollowType.caption)
        else
          _Report(cellar: cellar),
        const SizedBox(height: 12),
        FilledButton(
          key: const ValueKey('integrity-run'),
          onPressed: _checking ? null : _run,
          child: DualCopyText(
            _checking ? Copy.integrityRunning : Copy.integrityRun,
            style: HollowType.body,
          ),
        ),
      ],
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.cellar});

  final Cellar cellar;

  @override
  Widget build(BuildContext context) {
    final report = cellar.log.openReport;
    final unreadable = report.defects
        .where((defect) => defect.kind == LogDefectKind.unreadable)
        .length;
    final torn = report.defects
        .where((defect) => defect.kind == LogDefectKind.tornTail)
        .length;

    final findings = <(CopyLine, int)>[
      (Copy.integrityUnreadable, unreadable),
      (Copy.integrityRepeated, report.duplicates),
      (Copy.integrityOrphaned, cellar.stock.unknownBottles.length),
      (Copy.integrityDuplicateAdds, cellar.stock.duplicateAdds.length),
    ];
    final clean = findings.every((finding) => finding.$2 == 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(
          clean ? Copy.integrityClean : Copy.integrityFound,
          style: HollowType.body.copyWith(
            color: clean ? HollowPalette.inkSoft : HollowPalette.rose,
          ),
        ),
        const SizedBox(height: 10),
        for (final (label, count) in findings)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Expanded(child: DualCopyText(label, style: HollowType.caption)),
                const SizedBox(width: 12),
                Text(
                  '$count',
                  style: HollowType.numeric.copyWith(
                    color: count == 0 ? HollowPalette.inkFaint : HollowPalette.rose,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DualCopyText(Copy.integrityCounted, style: HollowType.caption),
            ),
            const SizedBox(width: 12),
            Text('${report.events}', style: HollowType.numeric),
          ],
        ),
        // **A torn tail is reported and is not a finding.** It is what a process killed mid-append
        // leaves behind, the store discards it on the next write, and calling it corruption would
        // make every crash look like data loss. Said in one line rather than hidden, because "the
        // log ends mid-line" is a true fact about the file.
        if (torn > 0) ...[
          const SizedBox(height: 6),
          Text('torn tail: $torn', style: HollowType.caption),
        ],
      ],
    );
  }
}
