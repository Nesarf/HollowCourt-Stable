import 'dart:convert';
import 'dart:io';

/// **What a reader is allowed to change about a folder.**

///
/// The folders themselves are **derived** -- `foldersOf()` reads `extras['source']` and `extras['category']` off
/// the recipes, which is why a recipe that gains a category needs no migration and why a reader's own drink will
/// land in a folder without anybody deciding where folders come from. That was the right call when it was made.
///
/// What it does not allow is for a folder to be *the reader's*: its name is whatever the data happened to say,
/// its order is whatever the IBA's own order happened to be, and there is nowhere to write "this one is mine" or
/// "this is whose drink it is". The owner asked for that on 2026-09-25:
///
/// > 配方文件夹的相关信息要允许用户自定义
///
/// So this is an **override layer, not a replacement**: a folder keeps being derived, and a style may be laid over
/// it. Delete the style and the folder is exactly what it was -- which is also what makes the feature safe to add
/// to a library that already ships folders, and what makes "an update never overwrites your words" true.
final class FolderStyle {
  const FolderStyle({this.name, this.note, this.order, this.accent});

  /// The reader's own name for the folder. Empty or absent means "call it what the data calls it".
  final String? name;

  /// Free text: what the folder is for, or whose drinks are in it. A 友方酒 folder has to be able to say whose,
  /// which is section 15's rule rather than a nicety.
  final String? note;

  /// Where it sits among the folders. Absent keeps the derived order.
  final int? order;

  /// A colour of its own, as `#RRGGBB`. Absent means the interface's gold.
  final String? accent;

  bool get isEmpty => name == null && note == null && order == null && accent == null;

  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (note != null) 'note': note,
    if (order != null) 'order': order,
    if (accent != null) 'accent': accent,
  };

  factory FolderStyle.fromJson(Object? json) {
    if (json is! Map) return const FolderStyle();
    return FolderStyle(
      name: json['name'] as String?,
      note: json['note'] as String?,
      order: (json['order'] as num?)?.toInt(),
      accent: json['accent'] as String?,
    );
  }
}

/// The reader's folder styles, keyed by the folder's derived key (`source/category`).
final class FolderStyleStore {
  const FolderStyleStore(this.file);

  final File? file;

  Future<Map<String, FolderStyle>> read() async {
    final target = file;
    if (target == null || !target.existsSync()) return {};
    try {
      final decoded = jsonDecode(await target.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: FolderStyle.fromJson(entry.value),
      };
    } on FormatException {
      // **A damaged file must not lock a reader out of their own library.** The same rule the display settings
      // and the cellar follow: unreadable means empty, never an error screen.
      return {};
    } on FileSystemException {
      return {};
    }
  }

  Future<void> write(Map<String, FolderStyle> styles) async {
    final target = file;
    if (target == null) return;
    final keep = {
      for (final entry in styles.entries)
        if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
    };
    await target.parent.create(recursive: true);
    await target.writeAsString(const JsonEncoder.withIndent('  ').convert(keep));
  }
}
