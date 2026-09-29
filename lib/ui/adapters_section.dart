import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../adapters/declared.dart';
import '../adapters/registry.dart';
import 'adapters_providers.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'prism.dart';
import 'theme.dart';

/// Section 11's adapters: the seams, and which of them is a door rather than a sign.
///
/// **This screen was written when every switch was disabled, and it said why in the row rather than in a
/// tooltip.** The comment it carried is worth keeping, because it is what the file does whenever a seam is not
/// built: *"No adapter is available in this build, so the registry would refuse to enable one -- and a switch
/// that moved and then did nothing would be worse than one that plainly will not."*
///
/// **Which seams are doors is a property of the build, and this row follows the registry rather than a list of
/// its own.** Two of the four are implemented and two are not, and that difference is the point of the
/// architecture rather than a change to it: an implementation exists, `isAvailable` answers true for it, and the
/// row appears. What the screen does *not* do is treat a switch as decoration -- one that is offered here is
/// wired to the registry, and the sentence beside it is composed from the adapter's own disclosure rather than
/// written next to it.
///
/// **The bartender was one of the doors and is no longer.** It answers by asking a model served on the reader's
/// own machine, which is a deployment rather than a feature of the application -- so it came out of this build
/// instead of being offered as a switch that leads to a failed request.
class AdaptersSection extends ConsumerWidget {
  const AdaptersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(adapterRegistryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.cellarAdapters, style: HollowType.heading),
        const SizedBox(height: 10),
        // A rule between one adapter and the next: four switches stacked with only spacing between them read
        // as one block, which is what the reader's "the separation between options is not obvious" was about.
        // **Only what this build can actually run.** The owner's rule of 2026-09-25: 每一项功能必须要可以实现并
        // 使用，无法做到的就需要暂时隐藏，等以后确认可用了再放出. The declared seams stay in the code -- their
        // disclosures are written, their requirements are stated -- but a card that says "not built" is a feature
        // the reader can see and cannot use, which is exactly what the rule forbids. Releasing one later is
        // deleting this filter's effect on it, not writing it again.
        for (final (index, adapter) in declaredAdapters
            .where((adapter) => adapter.isAvailable)
            .indexed) ...[
          if (index > 0) const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: HollowRule(),
          ),
          _AdapterRow(
            label: _labelFor(adapter.kind),
            kind: adapter.kind,
            adapter: adapter,
            available: registry.isAvailable(adapter.kind),
            enabled: registry.isEnabled(adapter.kind),
          ),
        ],
      ],
    );
  }

  static CopyLine _labelFor(AdapterKind kind) => switch (kind) {
    AdapterKind.priceComparison => Copy.adapterPriceComparison,
    AdapterKind.barcode => Copy.adapterBarcode,
    AdapterKind.measurement => Copy.adapterMeasurement,
  };
}

class _AdapterRow extends ConsumerWidget {
  const _AdapterRow({
    required this.label,
    required this.kind,
    required this.adapter,
    required this.available,
    required this.enabled,
  });

  final CopyLine label;
  final AdapterKind kind;
  final Adapter adapter;
  final bool available;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DualCopyText(label, style: HollowType.body),
                    const SizedBox(height: 2),
                    // **The "not included in this build" line is gone, not hidden.** The section only renders
                    // adapters this build can run (the owner's rule, 2026-09-25), so a branch for the other case
                    // could never draw -- it was dead code kept alive by two tests asserting it never appeared.
                    // A reader is never told a feature is missing, because a feature that is missing is not
                    // shown at all; the disclosure belongs to the ones that are.
                    _Disclosure(adapter: adapter),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: enabled,
                // Null disables the control, which is what an unavailable adapter gets: the registry would
                // throw on enable, so the screen must not offer it. An available one gets the real callback.
                onChanged: available
                    ? (value) => ref.read(adapterRegistryProvider.notifier).setEnabled(kind, value)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// **The disclosure, in the screen's own words, from the adapter's own facts.**
///
/// The hosts and the payload keys are printed verbatim, because they are what the code does; the words around
/// them are `Copy` lines, because a sentence is display text and belongs in the UI layer. A local host gets
/// the stronger sentence, and it is chosen by looking at the address rather than by the adapter claiming it --
/// an adapter cannot promote itself out of the disclosure by describing itself as private.
class _Disclosure extends ConsumerWidget {
  const _Disclosure({required this.adapter});

  final Adapter adapter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disclosure = adapter.disclosure;
    final hosts = disclosure.hosts.join(', ');
    final keys = disclosure.payloadKeys.join(', ');
    final isLocal = disclosure.hosts.every(_isLoopback);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${ref.copy(Copy.adapterContacts)}$hosts · ${ref.copy(Copy.adapterSends)}$keys',
          style: HollowType.caption,
        ),
        // **Stated before the adapter can be switched on**, which is the point: a reader who enables a barcode
        // scanner and only then reads that it wants the camera has been told too late to decide.
        if (disclosure.needsCamera || disclosure.needsNetwork) ...[
          const SizedBox(height: 4),
          Text(
            [
              if (disclosure.needsCamera) ref.copy(Copy.adapterNeedsCamera),
              if (disclosure.needsNetwork) ref.copy(Copy.adapterNeedsNetwork),
            ].join(' · '),
            style: HollowType.caption.copyWith(color: HollowPalette.rose),
          ),
        ],
        if (disclosure.sendsAnythingAboutTheCellar)
          DualCopyText(
            Copy.adapterSendsCellar,
            style: HollowType.caption.copyWith(color: HollowPalette.inkFaint),
          ),
        if (isLocal)
          DualCopyText(
            Copy.adapterLocalHost,
            style: HollowType.caption.copyWith(color: HollowPalette.gold),
          ),
      ],
    );
  }

  static bool _isLoopback(String host) =>
      host == '127.0.0.1' || host == '::1' || host == 'localhost';
}
