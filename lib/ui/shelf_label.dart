import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/events/shelf_authoring.dart';
import 'l10n/copy_resolution.dart';
import 'l10n/dual_copy_text.dart';
import 'library.dart';
import 'theme.dart';

/// What to call a shelf, resolved once for every screen that names one.
///
/// **One function rather than a rule written twice.** The bar draws a shelf's name as a chip and as the caption over
/// the board, and the ingredients tab draws it on the card of anything standing there. Three drawing sites, one
/// answer -- and the answer has three cases that are easy to get subtly different:
///
///   * a shelf the reader named carries **their word**, which is data in the log;
///   * the built-in shelf carries **copy**, because the id `bar` is a key that every placement written before this
///     family existed points at, and nobody ever said the word "bar" to mean their shelf;
///   * anything else carries **its own id**, which is the honest answer for a shelf that arrived from a peer whose
///     declaration did not travel with the placements.
///
/// **The third case is not a fallback for laziness.** `ShelfBook.nameOf` already answers with the id when there is no
/// name, and showing it says *this is a shelf I have been told about and never named* rather than inventing a word
/// for somebody else's cupboard.
///
/// **A plain string, for dense surfaces.** A grid card has room for one line of caption and the rest of that card is
/// single-language already, so the ingredients tab calls this. Anything with room for the two-register display calls
/// [shelfName] instead.
String shelfLabel(WidgetRef ref, Cellar cellar, String shelfId) {
  if (cellar.shelves.isMine(shelfId)) return cellar.shelves.nameOf(shelfId);
  if (shelfId == builtInShelfId) return ref.copy(Copy.barShelfMain);
  return shelfId;
}

/// A shelf's name, as something to put on a screen that has room for both registers.
///
/// **`DualCopyText` for the built-in shelf and plain text for the others**, and the difference is not decoration: a
/// reader who has turned dual copy on is reading two languages at once everywhere else in this application, and a
/// chip that suddenly showed one would be the only surface in the build that ignored the setting. A reader's own
/// shelf has nothing to dual-copy -- it is one word they typed -- so it stays as it is.
Widget shelfName(WidgetRef ref, Cellar cellar, String shelfId, {TextStyle? style}) {
  if (cellar.shelves.isMine(shelfId)) {
    return Text(cellar.shelves.nameOf(shelfId), style: style);
  }
  if (shelfId == builtInShelfId) {
    return DualCopyText(Copy.barShelfMain, style: style);
  }
  return Text(shelfId, style: style);
}
