import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// **The copy the app reads must be the file the tests check.**
///
/// `data/drinks/library.json` and `data/names/names.json` are where the library is authored, edited and
/// cross-checked, and every other guard in this directory reads them from there. The application cannot read
/// them: it loads `assets/drinks/library.json` and `assets/names/names.json`, which are **second copies**.
///
/// They were kept in step by hand until 2026-09-23, when they were fifteen drinks apart -- `data/` had 103
/// drinks and the bundle had 88 -- which is how the Windows build shipped a drink list that was missing Old
/// Fashioned while every test was green. The two failures were invisible to each other: the tests read one file
/// and the app read the other.
///
/// `packaging/sync_assets.sh` performs the copy. This test is what makes forgetting it a red suite rather than a
/// release that quietly loses a feature.
void main() {
  const pairs = {
    'drinks/library.json': 'the drink library',
    'names/names.json': 'the names and instructions',
  };

  for (final entry in pairs.entries) {
    test('**the shipped ${entry.value} is byte-identical to the authored one**', () {
      final data = File('data/${entry.key}');
      final asset = File('assets/${entry.key}');
      expect(data.existsSync(), isTrue, reason: 'run this from the repository root');
      expect(asset.existsSync(), isTrue, reason: 'the bundle has no ${entry.key} at all');

      final fromData = data.readAsBytesSync();
      final fromAsset = asset.readAsBytesSync();
      if (!_same(fromData, fromAsset)) {
        final drinks = _drinks(fromData);
        final shippedDrinks = _drinks(fromAsset);
        fail(
          'assets/${entry.key} differs from data/${entry.key}'
          '${drinks == null ? '' : ' ($drinks drinks authored, $shippedDrinks shipped)'}.\n'
          'Run: bash packaging/sync_assets.sh',
        );
      }
    });
  }
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// How many drinks a library file holds, for the failure message -- a count is what makes the drift obvious.
int? _drinks(List<int> bytes) {
  try {
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final counts = decoded['counts'];
    if (counts is Map) return counts['drinks'] as int?;
    final recipes = decoded['recipes'];
    if (recipes is Map) return recipes.length;
    return null;
  } on Object {
    return null;
  }
}
