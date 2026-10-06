import 'package:flutter/material.dart';

import 'ingredient_section.dart';

/// The 原料 tab.
///
/// **A page rather than a section, by the owner's instruction of 2026-10-06**: it had lived at the bottom of 设置,
/// and it is a peer of 酒窖 / 配方 / 记录 rather than something buried in an application's own settings -- a reader
/// manages what they own, and the bar is where what they own lives.
///
/// **The page is only a frame.** Everything it shows is [IngredientSection], which was written for the settings page
/// and did not have to change to move here: the section already carried its own heading, its own search, its own
/// count and its own list. That is the dividend of having built it as a section rather than as a page in the first
/// place, and it is worth naming because the opposite -- a widget that knew it was a page -- would have meant
/// rewriting it to move it.
class IngredientsPage extends StatelessWidget {
  const IngredientsPage({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      // The page scrolls and the grid inside it does not -- see the note on the grid, where two nested scroll
      // regions are the thing that makes a long list feel like it is fighting the finger.
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: const IngredientSection(),
    ),
  );
}
