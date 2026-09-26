import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/sync/names.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'sync_names.dart';
import 'theme.dart';

/// The two names, and which one goes out.
///
/// **This section exists because the owner asked for it in so many words**: *"在设置一栏里，里面可以给自己
/// 的空庭命名，然后对外同步的时候可以选择'同步时使用的名义'，即设备名称和空庭名称二选一。"* It is on the
/// settings page rather than beside the sync controls on 记录 because it is a fact about *this* device --
/// what it is called -- rather than about a particular exchange.
///
/// The distinction it draws, which the copy has to carry: **the name is a label and the fingerprint is the
/// identity.** Switching names never makes one device look like another, and a stranger copying a familiar
/// name gains nothing, because the fingerprint travels beside the name and is not theirs to copy.
class NamesSection extends ConsumerWidget {
  const NamesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(syncNamesProvider).value;
    final notifier = ref.read(syncNamesProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.namesTitle, style: HollowType.heading),
        const SizedBox(height: 6),
        DualCopyText(Copy.namesNote, style: HollowType.caption),
        const SizedBox(height: 16),

        // **A field that shows what is stored and writes when it is left.** The value is read from the
        // provider rather than owned by the field, so a change made anywhere else is reflected here -- and
        // the controller is rebuilt from it, which is why the field takes a key.
        if (names == null)
          const LinearProgressIndicator(minHeight: 2)
        else ...[
          _NameField(
            key: ValueKey('device-${names.deviceName}'),
            label: Copy.namesDevice,
            hint: Copy.namesDeviceHint,
            initial: names.deviceName,
            onSubmitted: notifier.setDeviceName,
          ),
          const SizedBox(height: 14),
          _NameField(
            key: ValueKey('cellar-${names.cellarName}'),
            label: Copy.namesCellar,
            hint: Copy.namesCellarHint,
            initial: names.cellarName,
            onSubmitted: notifier.setCellarName,
          ),
          const SizedBox(height: 18),

          DualCopyText(Copy.namesChoice, style: HollowType.caption),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('name-choice-device'),
                label: Text(ref.copy(Copy.namesUseDevice), style: HollowType.caption),
                selected: names.shows == NameChoice.device,
                onSelected: (_) => notifier.setChoice(NameChoice.device),
              ),
              ChoiceChip(
                key: const ValueKey('name-choice-cellar'),
                label: Text(ref.copy(Copy.namesUseCellar), style: HollowType.caption),
                selected: names.shows == NameChoice.cellar,
                onSelected: (_) => notifier.setChoice(NameChoice.cellar),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // What other devices will actually see, spelled out -- because "which name am I showing" is not
          // a question a reader should have to work out from two controls.
          _Line(
            label: Copy.namesShownAs,
            value: names.presented,
          ),
          // And the state that would otherwise be silent: the cellar name was chosen before the cellar
          // was named. The application keeps working (the device name goes out), and the reader is told
          // rather than left to wonder.
          if (names.wantsAnUnnamedCellar) ...[
            const SizedBox(height: 8),
            DualCopyText(
              Copy.namesUnnamedCellar,
              style: HollowType.caption.copyWith(color: HollowPalette.rose),
            ),
          ],
        ],
      ],
    );
  }
}

class _NameField extends StatefulWidget {
  const _NameField({
    super.key,
    required this.label,
    required this.hint,
    required this.initial,
    required this.onSubmitted,
  });

  final CopyLine label;
  final CopyLine hint;
  final String initial;
  final Future<void> Function(String) onSubmitted;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      DualCopyText(widget.label, style: HollowType.caption),
      const SizedBox(height: 6),
      TextField(
        controller: _controller,
        style: HollowType.body,
        decoration: InputDecoration(isDense: true, hintText: widget.hint.primary.text),
        // Written when the field is left rather than on every keystroke: a name is written to a file, and
        // a file write per character is a file write per character.
        onSubmitted: widget.onSubmitted,
        onTapOutside: (_) => widget.onSubmitted(_controller.text),
      ),
    ],
  );
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
