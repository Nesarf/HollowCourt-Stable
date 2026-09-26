import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/folder_styles.dart';

/// Where the reader's folder styles live: **beside the cellar, not inside the build.**
///
/// `cellar.ndjson` and `display.json` follow the same rule, and it is the rule that makes the promise true --
/// what a reader writes about their own library survives an update, because no update writes there.
final folderStylesFileProvider = FutureProvider<File>((Ref ref) async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}folder_styles.json');
});

/// The reader's folder styles, read once and kept.
///
/// **Empty is a valid answer and the common one.** A reader who has never renamed a folder has no styles at all,
/// and every folder is then exactly what the data derives -- which is why the feature can be added to a library
/// that already ships folders without touching a single recipe.
final folderStylesProvider = FutureProvider<Map<String, FolderStyle>>((Ref ref) async {
  final file = await ref.watch(folderStylesFileProvider.future);
  return FolderStyleStore(file).read();
});
