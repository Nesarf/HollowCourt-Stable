import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/sync/courtpack_service.dart';
import 'library.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'sync_identity.dart';
import 'sync_names.dart';
import 'theme.dart';

/// The directory packs live in: **the same one as the cellar**, so a reader who has found one has found the
/// other, and copying a pack in from a USB stick is a file operation with no dialog to fight.
final packDirectoryProvider = FutureProvider<String>((ref) async {
  final directory = await getApplicationDocumentsDirectory();
  return directory.path;
});

/// The packs sitting there now, and what the last import did.
final packListProvider = FutureProvider.autoDispose<List<File>>((ref) async {
  final directory = await ref.watch(packDirectoryProvider.future);
  return const CourtPackService().find(directory);
});

/// **The carrier that works when nothing else does: a file on a stick.**
///
/// `courtpack.dart` was written and called from nowhere, which made it a design with an implementation. This is
/// the screen half: export the cellar to a file, see the packs sitting beside it, and import one.
///
/// **Why it earns its place beside a working socket.** The socket needs two devices on one reachable network,
/// which is exactly what is missing in the places somebody wants to move a cellar: a hotel wireless with client
/// isolation, a phone that has been offline for a week, a desktop and a laptop never switched on at the same
/// time, two buildings. A pack travels on a stick, in a chat message, on a share.
///
/// **A pack is not trusted and not a backup**, and the screen says so where it is used rather than in a manual.
/// The header names who wrote it and when, and nothing proves it; what protects the reader is that an import is
/// always a **merge** into their own log, with the log's own rules -- additive where the operations are
/// additive, ordered by HLC where they are not. Importing a pack twice applies nothing the second time, and the
/// screen says that too, because "0 of 12 new" looks like a failure and is not one.
class PackCarrier extends ConsumerStatefulWidget {
  const PackCarrier({super.key});

  @override
  ConsumerState<PackCarrier> createState() => _PackCarrierState();
}

class _PackCarrierState extends ConsumerState<PackCarrier> {
  String? _written;
  CourtPackImport? _outcome;
  bool _busy = false;

  Future<void> _export() async {
    final cellar = ref.read(cellarProvider).value;
    final directory = await ref.read(packDirectoryProvider.future);
    if (cellar == null) return;
    setState(() => _busy = true);
    try {
      final file = await const CourtPackService().write(
        cellar.log,
        directory: directory,
        source: ref.read(syncNamesProvider).value?.deviceName ?? 'this device',
        fingerprint: ref.read(syncIdentityProvider).value?.identity.fingerprint ?? '',
      );
      if (!mounted) return;
      setState(() {
        _written = file.path;
        _outcome = null;
      });
      ref.invalidate(packListProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(File file) async {
    final cellar = ref.read(cellarProvider).value;
    if (cellar == null) return;
    setState(() => _busy = true);
    try {
      final outcome = await const CourtPackService().read(file, cellar.log);
      if (!mounted) return;
      setState(() => _outcome = outcome);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packs = ref.watch(packListProvider).value ?? const <File>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.packTitle, style: HollowType.title),
        const SizedBox(height: 6),
        DualCopyText(Copy.packNote, style: HollowType.caption),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton(
              key: const ValueKey('pack-export'),
              onPressed: _busy ? null : _export,
              child: DualCopyText(Copy.packExport, style: HollowType.body),
            ),
            const SizedBox(width: 12),
            if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator()),
          ],
        ),
        if (_written != null) ...[
          const SizedBox(height: 8),
          DualCopyText(Copy.packWritten, style: HollowType.caption),
          const SizedBox(height: 4),
          SelectableText(_written!, style: HollowType.numeric),
        ],

        const SizedBox(height: 16),
        DualCopyText(Copy.packFound, style: HollowType.caption),
        const SizedBox(height: 6),
        if (packs.isEmpty)
          DualCopyText(Copy.packNone, style: HollowType.caption)
        else
          for (final pack in packs)
            ListTile(
              key: ValueKey('pack-${pack.path}'),
              dense: true,
              // Not `const`: the palette is one mutable global and a const widget would freeze the
              // colour it was built with (see the design's rule on colours and const).
              leading: Icon(Icons.inventory_2_outlined, color: HollowPalette.gold),
              title: Text(_basename(pack.path), style: HollowType.body),
              trailing: TextButton(
                onPressed: _busy ? null : () => _import(pack),
                child: DualCopyText(Copy.packImport, style: HollowType.body),
              ),
            ),

        if (_outcome != null) ...[
          const SizedBox(height: 10),
          // **What happened, in the reader's words.** A refusal names which of the five reasons it was, because
          // "it did not work" would send somebody to check the wrong thing -- and an import that applied
          // nothing is reported as the success it is rather than as a failure.
          Text(
            _outcome!.ok
                ? '${ref.copy(Copy.packApplied)} ${_outcome!.applied} / ${_outcome!.offered}'
                : describePackProblem(_outcome!.problem!),
            key: const ValueKey('pack-outcome'),
            style: HollowType.body.copyWith(
              color: _outcome!.ok ? HollowPalette.gold : HollowPalette.rose,
            ),
          ),
        ],
      ],
    );
  }

  static String _basename(String path) =>
      path.split(Platform.pathSeparator).last;
}
