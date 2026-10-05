import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hollow_court/domain/sync/scope.dart';

/// **A new event type cannot become shareable without somebody deciding it should be.**
///
/// **[The defect these tests are for, found by review on 2026-10-01.]** `SyncKind.of` matched on prefixes --
/// `stock.`, `price.`, `overlay.` -- while the paragraph directly above it in the source promised the opposite:
/// *"a new event type added later is not shared until somebody decides it belongs in a scoped share."* A prefix
/// match decides it for them. The next `stock.something` written on purpose or by accident would travel in every
/// scoped share, with no decision recorded and no test failing.
///
/// The list is explicit now, and **this is the test that keeps it honest**, because an allowlist only stays an
/// allowlist if something notices when the set it is supposed to cover grows. It reads the event families out of
/// the source rather than being handed a hand-written copy, so a new event is caught by being written rather than
/// by somebody remembering to update a fixture.
void main() {
  /// The event type names declared in the log's own files.
  Set<String> declaredEventTypes() {
    // `flutter test` runs from the package root; the relative path is written both ways so the test does not
    // depend on which.
    final roots = [Directory('lib/domain/events'), Directory('../lib/domain/events')];
    final dir = roots.firstWhere((d) => d.existsSync(), orElse: () => roots.first);
    expect(dir.existsSync(), isTrue, reason: 'could not find the event sources from ${Directory.current.path}');

    final found = <String>{};
    for (final entry in dir.listSync()) {
      if (entry is! File || !entry.path.endsWith('.dart')) continue;
      final text = entry.readAsStringSync();
      // `static const name = 'a.b.c';` -- the shape every event family uses for its type names.
      // `static const bottleAdded = 'stock.bottle.added';` -- the shape every family uses. The **dot is
      // required**, which is what keeps a one-word constant like `prefix = 'own.'` out of the set.
      // **The type is optional and that is not a detail**: `price.dart` writes `static const String paid`, the
      // others write `static const paid`, and a pattern that required one shape silently found nothing in that
      // file -- which is exactly how a scanner quietly stops policing a family.
      for (final match in RegExp(r"static const (?:String )?\w+\s*=\s*'([a-z][a-z0-9]*\.[a-z0-9.]+)'")
          .allMatches(text)) {
        found.add(match.group(1)!);
      }
    }
    return found;
  }

  test('the scan finds the families it is supposed to police', () {
    // A scanner that silently finds nothing would make every assertion below vacuous, so it is checked first.
    final types = declaredEventTypes();
    expect(types.length, greaterThanOrEqualTo(8), reason: 'the scan found only ${types.length} event types');
    expect(types, contains('stock.bottle.added'));
    expect(types, contains('price.paid'));
  });

  test('**every stock, price and overlay event is either named in the allowlist or shares nothing**', () {
    // The three families this scope has an opinion about. An event under one of these prefixes reaching
    // `SyncKind.of` and getting `null` means it will not travel in a scoped share -- which is a decision, and the
    // point of this test is that it has to be a *made* one rather than an accident of which prefix somebody chose.
    const policed = ['stock.', 'price.', 'overlay.'];
    final types = declaredEventTypes().where((t) => policed.any(t.startsWith));
    expect(types, isNotEmpty, reason: 'the scan found no events in the policed families');

    final unregistered = <String>[];
    for (final type in types) {
      if (SyncKind.of(type) == null) unregistered.add(type);
    }
    // **Empty is the expected answer today**, and this line is what will fail when somebody adds a new
    // `stock.something`: they will then have to decide whether it is shared, and record the decision here.
    expect(
      unregistered,
      isEmpty,
      reason: 'these event types belong to a family the scope polices but are not named in `_shareable`, so they '
          'would silently not travel in a scoped share: $unregistered. If that is intended, say so by adding them '
          'to the expectation above rather than leaving them to be discovered by a reader whose bottles did not '
          'arrive.',
    );
  });

  test('**a recipe of the reader\'s own is not shareable, and that is a decision**', () {
    // The owner's instruction of 2026-10-01: custom recipes stay on this device for now. Those arriving here as
    // "not shareable" is the decision recorded, not an oversight -- and this assertion is what stops somebody
    // "fixing" the gap later without noticing that it was deliberate.
    for (final type in ['recipe.authored.set', 'recipe.authored.removed',
                        'recipe.collection.set', 'recipe.collection.cleared']) {
      expect(
        SyncKind.of(type),
        isNull,
        reason: '$type must not travel: a reader\'s own recipes are local until the owner decides otherwise',
      );
    }
  });

  test('an unknown event type is shareable by nothing', () {
    // The property the whole file rests on: a type nobody has classified travels in no scoped share.
    for (final unknown in ['stock.unknown.future', 'price.something.new', 'overlay.whatever', 'brand.new.family']) {
      expect(SyncKind.of(unknown), isNull, reason: unknown);
    }
  });
}
