import 'dart:convert';
import 'dart:io';

import '../domain/model/barcode.dart';

/// One remembered code.
final class BarcodeEntry {
  const BarcodeEntry({required this.ingredientId, this.name, this.addedAt});

  /// Which ingredient of the library this bottle turned out to be.
  final String ingredientId;

  /// What the label said, when the reader bothered to record it. The library's own name for the ingredient is
  /// usually enough; this is for the case where two gins are both gin and the reader wants to tell them apart.
  final String? name;

  /// When it was first scanned or typed, so a reader can see what they added rather than only what they have.
  final DateTime? addedAt;

  Map<String, Object?> toJson() => {
    'ingredientId': ingredientId,
    if (name != null) 'name': name,
    if (addedAt != null) 'addedAt': addedAt!.toIso8601String(),
  };

  factory BarcodeEntry.fromJson(Object? json) {
    if (json is! Map) return const BarcodeEntry(ingredientId: '');
    return BarcodeEntry(
      ingredientId: (json['ingredientId'] as String?) ?? '',
      name: json['name'] as String?,
      addedAt: DateTime.tryParse((json['addedAt'] as String?) ?? ''),
    );
  }
}

/// **The reader's own barcode registry: a code, remembered as an ingredient.**
///
/// This is the half of the feature that works with no camera, no permission and no network -- and it is the half
/// that makes the other half worth having. The first time a bottle arrives its code is unknown and the reader says
/// what it is; from then on that code resolves instantly, offline, on a plane, with the phone in aeroplane mode.
/// A catalogue lookup can *suggest* a name; only this can know that **this** bottle is the reader's gin.
///
/// **It is keyed on the canonical GTIN**, so a UPC-A typed in America and the same product's EAN-13 scanned in
/// Europe are one entry rather than two. That is the whole reason `barcode.dart` normalises to fourteen digits.
///
/// The file lives beside `cellar.ndjson`, on the same rule as everything else a reader writes: an update never
/// touches it, and a damaged one reads as empty rather than as fatal.
final class BarcodeRegistry {
  const BarcodeRegistry(this.file);

  final File? file;

  Future<Map<String, BarcodeEntry>> read() async {
    final target = file;
    if (target == null || !target.existsSync()) return {};
    try {
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String: BarcodeEntry.fromJson(entry.value),
      };
    } on FormatException {
      return {};
    } on FileSystemException {
      return {};
    }
  }

  /// What this code is, or null if the reader has never said. Both a typed and a scanned code arrive here, which
  /// is the point of the manual entry the owner asked for: the registry does not care how the digits were
  /// obtained.
  Future<BarcodeEntry?> lookup(String code) async {
    final canonical = canonicalBarcode(code);
    if (canonical.isEmpty) return null;
    return (await read())[canonical];
  }

  /// Records [code] as [ingredientId], replacing whatever was there.
  ///
  /// Replacing rather than refusing, because the reader is allowed to change their mind about a bottle -- and
  /// because a wrong entry with no way to correct it is worse than no entry at all.
  Future<void> remember(String code, String ingredientId, {String? name, DateTime? at}) async {
    final canonical = canonicalBarcode(code);
    if (canonical.isEmpty) return;
    final entries = await read();
    entries[canonical] = BarcodeEntry(
      ingredientId: ingredientId,
      name: name,
      addedAt: at ?? entries[canonical]?.addedAt ?? DateTime.now(),
    );
    await _write(entries);
  }

  Future<void> forget(String code) async {
    final canonical = canonicalBarcode(code);
    final entries = await read();
    if (entries.remove(canonical) == null) return;
    await _write(entries);
  }

  Future<void> _write(Map<String, BarcodeEntry> entries) async {
    final target = file;
    if (target == null) return;
    final keep = {
      for (final entry in entries.entries)
        if (entry.value.ingredientId.isNotEmpty) entry.key: entry.value.toJson(),
    };
    await target.parent.create(recursive: true);
    await target.writeAsString(const JsonEncoder.withIndent('  ').convert(keep));
  }
}
