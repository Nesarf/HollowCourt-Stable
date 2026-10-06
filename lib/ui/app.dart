import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/dual_copy_text.dart';
import 'cellar_page.dart';
import 'library.dart';
import 'recipes_page.dart';
import 'display_providers.dart';
import 'ornament.dart';
import 'theme_crossfade.dart';
import 'ingredients_page.dart';
import 'settings_page.dart';
import 'stock_page.dart';
import 'l10n/locale_providers.dart';
import 'hollow_nav_bar.dart';
import 'materials.dart';
import 'theme.dart';

/// The four tabs of section 12.3, and the shell around them.
///
/// | Tab | Section 12.3 | Here |
/// | --- | --- | --- |
/// | Stock | entry, browsing, remaining, expiry, prices | **P1**: record a bottle and list the shelf |
/// | Bar | visualised shelves | P2, and it says so rather than showing fake shelves |
/// | Recipes | list with match badges, filters | **P1**: scored against the shelf, makeability filter |
/// | Cellar | statistics, value, devices, sync | P2, and it says so |
///
/// **Two tabs are honest placeholders and that is deliberate.** Section 14 puts
/// shelf placement and statistics in P2. A page that showed an empty shelf would
/// be indistinguishable from a cellar that is genuinely empty, which is the one
/// thing a person must be able to tell apart -- so these two say which phase they
/// belong to instead.
class HollowCourtApp extends ConsumerWidget {
  const HollowCourtApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **The stored theme is applied here, before the first frame.** The palette is read by getters all
    // over the interface, so it has to be right before anything is built -- which is why the root
    // watches the setting rather than a leaf of the tree doing it. `displaySettingsProvider` also
    // applies it when the file arrives, for the window between the first paint and the read.
    final display = ref.watch(displaySettingsProvider);
    HollowPalette.use(display.theme);

    // The two settings the title below depends on: what the reader's language is, and whether they want both
    // scripts at once.
    final locale = ref.watch(localeSettingsProvider);
    final dual = ref.watch(dualCopyProvider);

    return MaterialApp(
      // The task switcher's single string, and it is paired on purpose: section 0.1
      // settled that this is where both scripts appear together, because Android
      // gives an application one line and this is the line.
      //
      // The setting exists now, and this is its first reader -- which is what this
      // comment predicted back when the value was a literal. Section 12.4's guard
      // makes the two lines different languages by construction, so `joined` cannot
      // produce `空庭 · 空庭`.
      // **The reader's own name for it.** With dual copy off this is the single line in their language --
      // 空庭, Hollow Court or 虚ろな庭 -- which is what the owner's correction asks for; with dual copy on it
      // is the pair, because Android's task switcher shows one string and this is the one it shows.
      title: dual
          ? Copy.appName.present(dualCopy: true).joined(' · ')
          : Copy.appName.textFor(locale.primaryTag),
      debugShowCheckedModeBanner: false,
      theme: HollowTheme.build(),
      // **The text size is applied here, in `builder`, and the placement is the point.** Wrapping `home`
      // would cover the pages and leave everything drawn in an overlay -- dialogs, dropdown menus,
      // tooltips -- at the platform's size, so a reader who asked for the larger step would get a page at
      // one size and a menu at another. `builder` wraps the navigator, so one scale reaches all of it.
      //
      // The platform's own scaler is read OUTSIDE the builder, from the context above `MaterialApp`, and
      // multiplied inside: `MaterialApp` installs a `MediaQuery` of its own, so reading it inside would be
      // reading back what this line had just written.
      builder: (context, child) {
        final platform = MediaQuery.of(context).textScaler;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: ScaledTextScaler(platform, display.textSize.scale),
          ),
          // **Here rather than in `home`, for the reason the text scale is here**: this is inside `MaterialApp`,
          // so the world in force is on the context and `precacheImage` has the `MediaQuery` it wants. It draws
          // nothing -- it exists so that a world with a picture does not show its colour change before the
          // picture arrives. See `WorldArtworkWarmer`.
          // **The fade wraps the warmer, so the veil covers the picture too.** The other order would fade the
          // interface and leave the artwork changing underneath it, which is the seam this exists to hide.
          // **The key is the whole fix for "the new world only appears where you scroll".**
          //
          // `HollowPalette` is global mutable state read through getters (`HollowPalette.ground` and fifteen
          // others, across thirty files). **Changing it notifies nobody.** So whether a given widget redraws in the
          // new world depends on whether something *else* happened to rebuild it: scrolling rebuilt the rows that
          // went past, which is why new colours arrived in patches, and switching tabs rebuilt nothing because
          // `IndexedStack` only changes which child is painted. The owner reported exactly that shape.
          //
          // **Keying the subtree by the world forces every one of those readers to run again**, because a changed
          // key makes Flutter discard the subtree and build a new one. It is not a tidy fix -- the honest one is an
          // `InheritedWidget` or a provider, so that a reader depends on the palette through the widget tree and
          // Flutter does the rest. That is recorded as debt rather than done here, because it touches the same
          // thirty files while three approved screens are still unbuilt, and rebuilding on top of a moving
          // foundation is how the next three mistakes get made.
          //
          // The key sits **below** `ThemeCrossfade`, so the veil keeps its state and can still fade across the
          // change it is announcing; put it above and the widget would be replaced before it could draw.
          child: ThemeCrossfade(
            child: WorldArtworkWarmer(
              child: KeyedSubtree(key: ValueKey(display.theme.name), child: child!),
            ),
          ),
        );
      },
      home: const _Shell(),
    );
  }
}

class _Shell extends ConsumerStatefulWidget {
  const _Shell();

  @override
  ConsumerState<_Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<_Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    // A build with no library says so once, at the top, rather than leaving a
    // person to wonder why every recipe reads as unmakable. It is a fact about
    // this checkout and not about their cellar.
    final seedMissing = ref.watch(seedProvider).value == null &&
        !ref.watch(seedProvider).isLoading;

    // **The reader's language, watched where it is drawn, and that is what makes the setting take effect
    // at once.** *"设定为选定语言选项后立刻更改显示语言（主语言和界面语言统一设定）"* -- a watch rebuilds this
    // widget on the next frame, and every string in the tree resolves through the same tag, so there is no
    // second place a language lives and nothing to keep in step. One `primaryTag` drives the main text and
    // the interface because in this application they are the same strings.
    final locale = ref.watch(localeSettingsProvider);

    return Scaffold(
      // **The instrument goes behind everything, and behind the banner too.** A background is only a
      // background if it is one layer: painting it inside the pages would have it scroll with them and
      // restart on every tab. The `Stack` is the shell's own, so the ornament is drawn once per frame
      // for the whole window.
      body: Stack(
        children: [
          // **Not `const`, and that is the whole bug this comment exists to prevent.** A `const` widget is built
          // once and never again, so this backdrop kept the palette it was born with -- the default world,
          // because the stored setting arrives asynchronously -- and went on drawing Amber Court's ground while
          // the rest of the screen had already turned to Winter. The colours followed the theme and the art did
          // not, which is precisely the fault a screenshot caught and no test could have.
          // **Not `const`, and that is the whole bug this comment exists to prevent.** A `const` widget is built
          // once and never again, so this backdrop kept the palette it was born with -- the default world, because
          // the stored setting arrives asynchronously -- and went on drawing Amber Court's ground while the rest
          // of the screen had already turned to Winter. The colours followed the theme and the art did not, which
          // is the fault a screenshot caught and no assertion about the palette could have.
          // `test/ui/world_art_fidelity_test.dart` fails if it ever becomes const again.
          Positioned.fill(child: OrnamentBackdrop()),
          Column(
            children: [
              if (seedMissing) const _LibraryBanner(),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  // **Not `const`, and this is the second time this exact fault has been in this file.**
                  //
                  // A `const` child is built once and never again, so these four pages kept the palette they
                  // were born with. **Changing the world repainted nothing until something else forced a
                  // rebuild** -- scrolling rebuilt the rows that went past, which is why new colours appeared in
                  // patches, and switching tabs rebuilt nothing at all because `IndexedStack` only changes which
                  // child is painted. The owner reported it in exactly that shape: *换主题后要等到页面刷新
                  // （比如说滚动屏幕让对应区域重新显示一遍，目前切换底部栏不能进行新渲染）才启用新渲染*.
                  //
                  // The comment above `OrnamentBackdrop` describes the same bug for the same reason, and that
                  // one was caught by a screenshot. **This is the same mistake in the same widget tree, which is
                  // the argument against treating either as a one-off**: `HollowPalette` is global state read
                  // through getters, so nothing rebuilds *because* the palette changed. Every widget that draws
                  // a colour has to be rebuilt by whoever owns it, and `const` is a promise that it will not be.
                  children: [
                    const StockPage(),
                    const RecipesPage(),
                    // Section 12.3 gives this tab statistics, a consumption curve, value, a
                    // shopping list, devices and sync. Only the value exists, so the page
                    // shows the value and keeps the sentence naming the rest -- replacing
                    // the placeholder outright would claim six features and ship one.
                    const CellarPage(),
                    // **原料, the fifth tab, by the owner's instruction of 2026-10-06.** It had been a section at
                    // the bottom of 设置 and is a peer of the other three rather than part of an application's own
                    // settings: a reader manages what they own, and the bar is where what they own lives.
                    const IngredientsPage(),
                    // Section 12.3's fifth tab, asked for by the owner: the application's own
                    // settings, which were a section at the bottom of 记录. Devices and sync stay
                    // there -- see `SettingsPage` for where the line is and why.
                    const SettingsPage(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      // **The application's own bar.** It used to be Material's `NavigationBar`, with Material's icon font in
      // every destination -- somebody else's design, on the furniture every screen carries. See
      // `hollow_nav_bar.dart` for what replaced it and why the motif is the indicator.
      // **Above the system's own bar, not under it.** The handset screenshot showed the app's navigation sitting
      // behind Android's three buttons, which is what a window that extends into the system insets looks like:
      // the labels were not overlapping the marks, they were *underneath the phone's own chrome*. The text-scale
      // clamp from the round before was a real fix for a real symptom, and this is the cause.
      bottomNavigationBar: SafeArea(
        top: false,
        child: HollowNavBar(
        selectedIndex: _index,
        onSelected: (index) => setState(() {
          _index = index;
          // **The room the reader is in, told to the palette.** The five screens are furnished differently and
          // every material is derived from this one value, so it has to change exactly when the tab does -- once,
          // here, rather than in five places that could disagree.
          currentRoom = RoomMaterial.values[index];
        }),
        destinations: hollowDestinations([
          Copy.tabStock.textFor(locale.primaryTag),
          Copy.tabRecipes.textFor(locale.primaryTag),
          Copy.tabCellar.textFor(locale.primaryTag),
          Copy.tabIngredients.textFor(locale.primaryTag),
          Copy.tabSettings.textFor(locale.primaryTag),
        ]),
        ),
      ),
    );
  }
}

class _LibraryBanner extends StatelessWidget {
  const _LibraryBanner();

  @override
  Widget build(BuildContext context) => Material(
    color: HollowPalette.surfaceRaised,
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 17, color: HollowPalette.rose),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DualCopyText(
                    Copy.noLibrary,
                    style: HollowType.caption.copyWith(color: HollowPalette.ink),
                  ),
                  const SizedBox(height: 2),
                  DualCopyText(Copy.noLibraryHint, style: HollowType.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A screen belonging to a later phase, saying so.
