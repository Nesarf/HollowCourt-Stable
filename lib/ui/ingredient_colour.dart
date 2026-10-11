import 'package:flutter/material.dart';

/// A colour per ingredient kind, for a bottle on a shelf.
///
/// ## Why a bottle had no colour, and why it has this one
///
/// `bar_page.dart`'s `_Bottle` was drawn in one grey, and the paragraph above it said why -- correctly:
///
/// > *Deliberately not a `LiquidSwatch`: that widget draws a drink in a glass from section 12.1's colour string,
/// > which is a fact about a recipe. A bottle on a shelf is a fact about a container, and painting the drink inside
/// > it would say the bottle holds one cocktail.*
///
/// **That reasoning is sound and the screen it produced was useless**, which is the pair worth holding together. The
/// owner's report of 2026-10-06 is the second half of it: *"没有颜色区分，很鸡肋，我就强制下架了"* -- no colour
/// differentiation, so the shelf is a wall of identical rectangles and there is no reason to look at it.
///
/// **So the answer is not to paint the drink. It is to find a fact about the ingredient.** There is exactly one that
/// is complete: `kind`, which `docs/ingredient-gap.md` measured at **189 of 189 ingredients** -- liqueur 43,
/// spirit 34, pantry 16, syrup 15, fruit 13, juice 13, wine 12, dairy 10, spice 10, mixer 10, bitter 4, tea 3,
/// garnish 3, beer 3.
///
/// **And it colours the way a bar is actually organised**, which is the argument that this is a real distinction
/// rather than a decoration: spirits stand together, liqueurs together, syrups and juices together. A shelf painted
/// this way can be read as *composition* from across a room.
///
/// ## What the colour does not claim
///
/// **It is a key, not a liquid.** A reader seeing a green bottle should not conclude the contents are green --
/// `créme de menthe` is, and so is a lime cordial, and a `spirit` is never the amber it is drawn in. **Which is why
/// the bottle carries its name as well** and the colour is never the only signal on it: the label is the truth and
/// the colour is a hint about the shelf.
///
/// ## The mapping
///
/// The idiom is `liquidColour`'s in `liquid_swatch.dart`, and for the same reason: a hue per family with the
/// saturation kept low, because twenty of these are on screen at once and section 20.3 asks for low-contrast
/// mid-tones rather than a signal. **The hues are spread over the wheel rather than matched to what the kind
/// usually looks like**, because matching would be the claim this file just refused to make.
Color ingredientKindColour(String? kind) {
  final (hue, saturation) = switch (kind) {
    // The two that stand together on any bar, and the two a reader looks for first.
    'spirit' => (36.0, 0.14),
    'liqueur' => (330.0, 0.30),
    // Ordered around the wheel so that neighbouring kinds are never neighbouring hues.
    'wine' => (356.0, 0.32),
    'beer' => (46.0, 0.40),
    'syrup' => (22.0, 0.36),
    'juice' => (12.0, 0.42),
    'fruit' => (96.0, 0.26),
    'mixer' => (205.0, 0.26),
    'bitter' => (268.0, 0.22),
    'tea' => (74.0, 0.22),
    'dairy' => (48.0, 0.05),
    'spice' => (18.0, 0.26),
    'garnish' => (128.0, 0.24),
    'pantry' => (30.0, 0.08),
    // **A kind this build does not know is grey, not a guess.** The rule the ingredients tab already follows for a
    // category it cannot read: returning a nearest match would silently reclassify somebody's record.
    _ => (36.0, 0.0),
  };

  return HSLColor.fromAHSL(1, hue, saturation, 0.52).toColor();
}
