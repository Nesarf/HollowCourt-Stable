/// Resolving a [CopyLine] the way the interface actually means it.
///
/// **Written because thirty-five call sites did not.** They read `Copy.lines.primary.text` -- which is the
/// *authored* sentence, always Chinese, resolved through nothing at all: not the reader's locale, and not
/// their voice. Every one of them was therefore a place where choosing a language, or choosing a voice,
/// changed nothing on screen, which makes both axes look broken at exactly the spots where somebody is
/// watching for them to work.
///
/// `DualCopyText` is the widget form of the same resolution and is what most screens use; where the string
/// is needed rather than a widget -- a `TextField`'s label, a message assembled with interpolation -- this
/// gives the same answer, from the same two providers, in one line:
///
/// ```dart
/// TextField(decoration: InputDecoration(labelText: ref.copy(Copy.barcodeLabel)))
/// Text('${ref.copy(Copy.barcodeKnown)} ${entry.name}')
/// ```
///
/// The voice is read through a `select` so that a widget rebuilds when the voice changes and not whenever
/// anything else in the display settings does -- the same narrow watch `DualCopyText` explains at length,
/// and for the same reason.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../display_providers.dart';
import 'dual_copy.dart';
import 'locale_providers.dart';

extension CopyResolution on WidgetRef {
  /// The reader's sentence: their language, in the voice they chose.
  ///
  /// Resolution itself is [CopyLine.textFor]'s, including the fallback chain, so this extension adds a
  /// lookup and no new rules. A line with no voice written for it returns exactly what it returned before
  /// there were voices at all, which is rule two of the voice axis.
  String copy(CopyLine line) {
    final settings = watch(localeSettingsProvider);
    final voice = watch(displaySettingsProvider.select((settings) => settings.voice));
    return line.textFor(settings.primaryTag, voice: voice);
  }
}
