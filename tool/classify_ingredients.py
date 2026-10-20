#!/usr/bin/env python3
"""Gives every shipped ingredient a `kind`, and a `family` where one refines it.

**Why this exists.** `docs/ingredient-gap.md` records the measurement: 189 ingredients of which **47 carried a
category** and **142 had none**, against an enum declaring 33 categories of which 17 are used. The proposal
(`docs/proposal-recipes-and-packs.md` §3) asks for a two-level shape -- `kind` required, `family` optional -- and a
test that every shipped ingredient has one. This is the pass that fills it in.

**What it is not.** It does not fetch anything. The project's own rule, quoted in the library's `note`, is that a
name and a classification are facts and a description is somebody's writing -- so this writes classifications and
nothing else. No prose, no composition lists, no tasting notes.

**The existing categories are mapped rather than discarded**, which the proposal asks for by name
(`portAndSherry` becomes `wine/sherry`). Where an ingredient already had one, the mapping below starts from it.

Usage:  python3 tool/classify_ingredients.py [--apply]
"""
from __future__ import annotations

import io
import json
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(REPO, 'assets', 'drinks', 'library.json')

# The existing category, mapped onto (kind, family). The left column is what the seed already said; the right is
# the two-level shape the proposal asks for. **Nothing is thrown away** -- an ingredient whose category was
# `commonLiqueurs` becomes `liqueur`, which is the same claim in the shape a picker can use.
CATEGORY_TO_KIND: dict[str, tuple[str, str | None]] = {
    'whiskey': ('spirit', 'whiskey'),
    'gin': ('spirit', 'gin'),
    'rum': ('spirit', 'rum'),
    'tequilaAndMezcal': ('spirit', 'agave'),
    'vodkaAndSimilar': ('spirit', 'vodka'),
    'brandy': ('spirit', 'brandy'),
    'beerAndCider': ('beer', None),
    'wine': ('wine', None),
    'commonLiqueurs': ('liqueur', None),
    'vermouth': ('wine', 'vermouth'),
    'portAndSherry': ('wine', 'fortified'),
    'aperitifs': ('liqueur', 'aperitif'),
    'commonAmaro': ('liqueur', 'amaro'),
    'commonBitters': ('bitter', None),
    'citrus': ('juice', 'citrus'),
    'juices': ('juice', None),
    'fruitAndVeg': ('fruit', None),
    'syrups': ('syrup', None),
    'jamsAndPreserves': ('pantry', 'preserve'),
    'herbsAndSpices': ('spice', 'herb'),
    'sodas': ('mixer', None),
    'pantryItems': ('pantry', None),
    'groceryItems': ('pantry', None),
}

# Every ingredient with no category, classified by hand. **The kind vocabulary is the proposal's**, with the
# families chosen so that a picker can offer something narrower than "spirit" without inventing a level the
# proposal does not have.
BY_HAND: dict[str, tuple[str, str | None]] = {
    # ---- spirits, by what they are distilled from ------------------------------------------------
    'absinthe': ('spirit', 'anise'),
    'pernod': ('spirit', 'anise'),
    'aguardiente': ('spirit', 'cane'),
    'cachaca': ('spirit', 'cane'),
    'soju': ('spirit', 'grain'),
    'irishWhiskey': ('spirit', 'whiskey'),
    'ryeWhiskey': ('spirit', 'whiskey'),
    'scotchWhisky': ('spirit', 'whiskey'),
    'whiskey': ('spirit', 'whiskey'),
    'appleBrandy': ('spirit', 'brandy'),
    'brandy': ('spirit', 'brandy'),
    'kirschEauDeVie': ('spirit', 'brandy'),
    'pisco': ('spirit', 'brandy'),
    'mezcal': ('spirit', 'agave'),
    'tequila': ('spirit', 'agave'),
    'darkRum': ('spirit', 'rum'),
    'goldRum': ('spirit', 'rum'),
    'spicedRum': ('spirit', 'rum'),
    'whiteRum': ('spirit', 'rum'),
    'prosecco': ('spirit', 'sparkling'),
    # ---- liqueurs --------------------------------------------------------------------------------
    'amaretto': ('liqueur', 'nut'),
    'advocaat': ('liqueur', 'egg'),
    'irishCreamLiqueur': ('liqueur', 'cream'),
    'blueCuracao': ('liqueur', 'orange'),
    'orangeCuracao': ('liqueur', 'orange'),
    'orangeLiqueur': ('liqueur', 'orange'),
    'tripleSec': ('liqueur', 'orange'),
    'greenChartreuse': ('liqueur', 'herbal'),
    'yellowChartreuse': ('liqueur', 'herbal'),
    'benedictine': ('liqueur', 'herbal'),
    'drambuie': ('liqueur', 'herbal'),
    'galliano': ('liqueur', 'herbal'),
    'sambuca': ('liqueur', 'anise'),
    'pimmS': ('liqueur', 'fruit'),
    'sloeGin': ('liqueur', 'fruit'),
    'blackberryLiqueur': ('liqueur', 'fruit'),
    'blackcurrantLiqueur': ('liqueur', 'fruit'),
    'cherryLiqueur': ('liqueur', 'fruit'),
    'passionfruitLiqueur': ('liqueur', 'fruit'),
    'peachLiqueur': ('liqueur', 'fruit'),
    'raspberryLiqueur': ('liqueur', 'fruit'),
    'apricotLiqueur': ('liqueur', 'fruit'),
    'bananaLiqueur': ('liqueur', 'fruit'),
    'melonLiqueur': ('liqueur', 'fruit'),
    'peachSchnapps': ('liqueur', 'fruit'),
    'peppermintSchnapps': ('liqueur', 'mint'),
    'greenCremeDeMenthe': ('liqueur', 'mint'),
    'whiteCremeDeMenthe': ('liqueur', 'mint'),
    'cremeDeMenthe': ('liqueur', 'mint'),
    # ---- bitters and amari -----------------------------------------------------------------------
    'angosturaBitters': ('bitter', None),
    'orangeBitters': ('bitter', None),
    'peachBitters': ('bitter', None),
    'peychaudSBitters': ('bitter', None),
    'amaro': ('liqueur', 'amaro'),
    'aperol': ('liqueur', 'aperitif'),
    'campari': ('liqueur', 'aperitif'),
    'cynar': ('liqueur', 'amaro'),
    'fernet': ('liqueur', 'amaro'),
    'jagermeister': ('liqueur', 'amaro'),
    'suze': ('liqueur', 'aperitif'),
    # ---- wines -----------------------------------------------------------------------------------
    'lilletBlanc': ('wine', 'aperitif'),
    'redWine': ('wine', None),
    'whiteWine': ('wine', None),
    'champagne': ('wine', 'sparkling'),
    'creamSherry': ('wine', 'fortified'),
    'drySherry': ('wine', 'fortified'),
    'dryVermouth': ('wine', 'vermouth'),
    'rubyPort': ('wine', 'fortified'),
    'tawnyPort': ('wine', 'fortified'),
    # ---- beer and cider --------------------------------------------------------------------------
    'hardCider': ('beer', None),
    'lager': ('beer', None),
    'stout': ('beer', None),
    # ---- juices and mixers -----------------------------------------------------------------------
    'appleJuice': ('juice', None),
    'cranberryJuice': ('juice', None),
    'grapefruitJuice': ('juice', None),
    'guavaJuice': ('juice', None),
    'limeJuice': ('juice', 'citrus'),
    'lemonJuice': ('juice', 'citrus'),
    'lycheeJuice': ('juice', None),
    'orangeJuice': ('juice', 'citrus'),
    'pineappleJuice': ('juice', None),
    'pomegranateJuice': ('juice', None),
    'sugarCaneJuice': ('juice', None),
    'tomatoJuice': ('juice', 'vegetable'),
    'coconutWater': ('juice', None),
    'cola': ('mixer', None),
    'energyDrink': ('mixer', None),
    'gingerAle': ('mixer', None),
    'gingerBeer': ('mixer', None),
    'lemonade': ('mixer', None),
    'orangeSoda': ('mixer', None),
    'tonicWater': ('mixer', None),
    'water': ('mixer', None),
    # ---- syrups ----------------------------------------------------------------------------------
    'agaveSyrup': ('syrup', None),
    'almondSyrup': ('syrup', 'nut'),
    'cinnamonSyrup': ('syrup', 'spice'),
    'elderflowerCordial': ('syrup', 'floral'),
    'grenadine': ('syrup', 'pomegranate'),
    'mapleSyrup': ('syrup', None),
    'raspberrySyrup': ('syrup', 'berry'),
    'simpleSyrup': ('syrup', None),
    'strawberrySyrup': ('syrup', 'berry'),
    # ---- tea, and the things that are neither food nor drink -------------------------------------
    'blackTea': ('tea', None),
    'earlGreyTea': ('tea', None),
    'greenTea': ('tea', None),
    'falernum': ('syrup', 'spice'),
    # ---- dairy and eggs --------------------------------------------------------------------------
    'condensedMilk': ('dairy', None),
    'cream': ('dairy', None),
    'creamOfCoconut': ('dairy', None),
    'iceCream': ('dairy', None),
    'lemonSorbet': ('dairy', None),
    'milk': ('dairy', None),
    'egg': ('dairy', 'egg'),
    'eggWhite': ('dairy', 'egg'),
    'eggYolk': ('dairy', 'egg'),
    'aquafaba': ('dairy', 'egg'),
    # ---- spices and herbs ------------------------------------------------------------------------
    'basilLeaf': ('spice', 'herb'),
    'cinnamon': ('spice', 'spice'),
    'corianderLeaf': ('spice', 'herb'),
    'mintLeaf': ('spice', 'herb'),
    'nutmeg': ('spice', 'spice'),
    'sageLeaf': ('spice', 'herb'),
    'chilliPepper': ('spice', 'spice'),
    'chilliPowder': ('spice', 'spice'),
    'coffeeBeans': ('spice', 'coffee'),
    # ---- fruit and vegetables --------------------------------------------------------------------
    'apple': ('fruit', None),
    'blackberry': ('fruit', 'berry'),
    'grapefruit': ('fruit', 'citrus'),
    'lemon': ('fruit', 'citrus'),
    'lime': ('fruit', 'citrus'),
    'orange': ('fruit', 'citrus'),
    'passionfruit': ('fruit', None),
    'peach': ('fruit', 'stone'),
    'pineapple': ('fruit', None),
    'bellPepper': ('fruit', 'vegetable'),
    'cucumber': ('fruit', 'vegetable'),
    'strawberry': ('fruit', 'berry'),
    'raspberry': ('fruit', 'berry'),
    # ---- garnishes -------------------------------------------------------------------------------
    'olive': ('garnish', None),
    'pickledOnion': ('garnish', None),
    'cherry': ('garnish', None),
    # ---- pantry ----------------------------------------------------------------------------------
    'brownSugar': ('pantry', None),
    'sugar': ('pantry', None),
    'chocolate': ('pantry', None),
    'coffee': ('pantry', 'coffee'),
    'espressoCoffee': ('pantry', 'coffee'),
    'oliveBrine': ('pantry', 'brine'),
    'pickleBrine': ('pantry', 'brine'),
    'orangeMarmalade': ('pantry', 'preserve'),
    'sesameOil': ('pantry', None),
    'vanillaExtract': ('pantry', None),
    'rosewater': ('pantry', 'floral'),
    'orangeFlowerWater': ('pantry', 'floral'),
    'honey': ('pantry', 'syrup'),
    'salt': ('pantry', None),
    'pepper': ('pantry', 'spice'),

    # ---- the 38 that used to be classified by `category` -------------------------------------------
    #
    # **These were never unclassified; they carried a category until the taxonomy split.** On 2026-10-01 the
    # twenty-seven substance categories were retired in favour of `kind`/`family`, and the 47 ingredients that had
    # one had their category *converted* rather than deleted -- this list is that conversion, written down so the
    # reason survives. Each line's comment names the category it came from, which is why the families look
    # deliberate: they are.
    'allspiceDram': ('liqueur', 'herbal'),           # commonLiqueurs
    'coffeeLiqueur': ('liqueur', 'coffee'),          # commonLiqueurs
    'cremeDeCacao': ('liqueur', 'cacao'),            # commonLiqueurs
    'cremeDeCassis': ('liqueur', 'fruit'),           # commonLiqueurs
    'cremeDeViolette': ('liqueur', 'floral'),        # commonLiqueurs
    'frangelico': ('liqueur', 'nut'),                # commonLiqueurs
    'maraschinoLiqueur': ('liqueur', 'fruit'),       # commonLiqueurs
    'amontilladoSherry': ('wine', 'fortified'),      # portAndSherry
    'paloCortado': ('wine', 'fortified'),            # portAndSherry
    'sweetVermouth': ('wine', 'vermouth'),           # vermouth
    'sparklingWine': ('wine', 'sparkling'),          # wine
    'blendedAgedRum': ('spirit', 'rum'),             # rum
    'cubanRum': ('spirit', 'rum'),                   # rum
    'demeraraRum': ('spirit', 'rum'),                # rum
    'overproofRum': ('spirit', 'rum'),               # rum
    'rhumAgricole': ('spirit', 'rum'),               # rum
    'smokyRum': ('spirit', 'rum'),                   # rum
    'bourbonWhiskey': ('spirit', 'whiskey'),         # whiskey
    'calvados': ('spirit', 'brandy'),                # brandy
    'cognac': ('spirit', 'brandy'),                  # brandy
    'grappa': ('spirit', 'brandy'),                  # brandy
    'peachBrandy': ('spirit', 'brandy'),             # brandy
    'gin': ('spirit', 'gin'),                        # gin
    'oldTomGin': ('spirit', 'gin'),                  # gin
    'vodka': ('spirit', 'vodka'),                    # vodkaAndSimilar
    'vanillaVodka': ('spirit', 'vodka'),             # vodkaAndSimilar
    'chamomileCordial': ('syrup', 'floral'),         # syrups
    'honeySyrup': ('syrup', None),                   # syrups
    'orgeat': ('syrup', 'nut'),                      # syrups
    'passionfruitSyrup': ('syrup', None),            # syrups
    'vanillaSyrup': ('syrup', None),                 # syrups
    'ginger': ('spice', 'spice'),                    # herbsAndSpices
    'grape': ('fruit', None),                        # fruitAndVeg
    'peachPure': ('fruit', 'stone'),                 # fruitAndVeg
    'grapefruitSoda': ('mixer', None),               # sodas
    'sodaWater': ('mixer', None),                    # sodas
    'hotSauce': ('pantry', None),                    # pantryItems
    'worcestershireSauce': ('pantry', None),         # pantryItems
}


def classify(ingredient: dict) -> tuple[str, str | None] | None:
    """The kind and family for one ingredient, or None when nobody has said."""
    if ingredient['id'] in BY_HAND:
        return BY_HAND[ingredient['id']]
    category = ingredient.get('category')
    if category is not None and category in CATEGORY_TO_KIND:
        return CATEGORY_TO_KIND[category]
    return None


def main() -> int:
    apply = '--apply' in sys.argv
    data = json.load(io.open(SEED, encoding='utf-8'))

    missing: list[str] = []
    changed = 0
    for ingredient in data['ingredients']:
        pair = classify(ingredient)
        if pair is None:
            missing.append(ingredient['id'])
            continue
        kind, family = pair
        if ingredient.get('kind') != kind or ingredient.get('family') != family:
            changed += 1
        ingredient['kind'] = kind
        if family is not None:
            ingredient['family'] = family
        else:
            ingredient.pop('family', None)

    kinds: dict[str, int] = {}
    for ingredient in data['ingredients']:
        if 'kind' in ingredient:
            kinds[ingredient['kind']] = kinds.get(ingredient['kind'], 0) + 1

    print('%d ingredients, %d changed, %d unclassified' % (len(data['ingredients']), changed, len(missing)))
    print()
    print('kinds:')
    for kind, count in sorted(kinds.items(), key=lambda kv: -kv[1]):
        print('  %-10s %3d' % (kind, count))
    if missing:
        print()
        print('**no kind decided for:**')
        for name in missing:
            print('  ', name)

    if apply and not missing:
        io.open(SEED, 'w', encoding='utf-8', newline='\n').write(
            json.dumps(data, ensure_ascii=False, indent=2) + '\n'
        )
        print()
        print('written to %s' % SEED)
    elif apply:
        print()
        print('refusing to write while anything is unclassified')
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
