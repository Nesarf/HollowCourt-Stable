import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:io';

import '../domain/events/stock.dart';
import 'adapters_section.dart';
import 'library.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'theme.dart';

/// What this build is made of: the log it is running on, and the seams it does not open.
///
/// **This is where the four "not implemented in this build" rows went.** They used to be on the
/// Cellar tab, under 设备与同步, and each said 这个构建里还没有实现，所以打不开 -- so a reader opening the
/// screen that shows their cellar was told four times that something did not exist. The seams are
/// real (they are in the code, they have kinds and a registry), so what belongs on a reader's screen
/// is nothing at all, and what belongs here is what they actually are: four doors this build does
/// not include, listed where somebody looking at the build would look.
///
/// **And the numbers are the fold's, not a re-count.** `StockLedger` already reports what it could
/// not read, what it saw twice and what named a bottle that is not there; until now the only way to
/// see any of it was to write a test. A screen that shows the same values the application is
/// actually acting on is a diagnostic; a screen that counted for itself would be a second opinion
/// nobody asked for.
class DeveloperSection extends ConsumerWidget {
  const DeveloperSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cellar = ref.watch(cellarProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.developerHeading, style: HollowType.heading),
        const SizedBox(height: 10),
        DualCopyText(Copy.developerIntro, style: HollowType.caption),
        const SizedBox(height: 18),

        DualCopyText(Copy.developerLogHeading, style: HollowType.title),
        const SizedBox(height: 8),
        if (cellar == null)
          DualCopyText(Copy.integrityNoLog, style: HollowType.caption)
        else ...[
          _Row(label: Copy.developerLogPath, value: cellar.log.store.file.path),
          _Row(label: Copy.developerLogEvents, value: '${cellar.log.events.length}'),
          _Row(label: Copy.developerLogBytes, value: '${_bytesOf(cellar.log.store.file)}'),
          _Row(label: Copy.developerLogNode, value: cellar.log.clock.nodeId),
          const SizedBox(height: 8),
          _FoldCounts(stock: cellar.stock),
        ],

        const SizedBox(height: 20),
        DualCopyText(Copy.developerSeamsHeading, style: HollowType.title),
        const SizedBox(height: 6),
        DualCopyText(Copy.developerSeamsNote, style: HollowType.caption),
        const SizedBox(height: 10),
        // The same widget the Cellar tab used to carry, moved rather than rewritten -- but its rows
        // no longer apologise; see `adapters_section.dart` for what each one says now.
        const AdaptersSection(),
      ],
    );
  }

  static int _bytesOf(File file) => file.existsSync() ? file.lengthSync() : 0;
}

/// What the fold did with the log, in the fold's own words.
class _FoldCounts extends StatelessWidget {
  const _FoldCounts({required this.stock});

  final StockLedger stock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(
          label: Copy.integrityCounted,
          value: '${stock.appliedEvents} applied / ${stock.ignoredEvents} ignored',
        ),
        _Row(label: Copy.integrityOrphaned, value: '${stock.unknownBottles.length}'),
        _Row(label: Copy.integrityDuplicateAdds, value: '${stock.duplicateAdds.length}'),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final CopyLine label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: DualCopyText(label, style: HollowType.caption)),
          const SizedBox(width: 12),
          Flexible(
            child: SelectableText(
              value,
              style: HollowType.numeric,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
