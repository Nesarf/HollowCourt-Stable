import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/dual_copy_text.dart';
import 'bar_page.dart';
import 'cellar_page.dart';
import 'library.dart';
import 'recipes_page.dart';
import 'display_providers.dart';
import 'ornament.dart';
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
                  children: const [
                    StockPage(),
                    // Built, as of P2's first pass: the shelf, the bottles standing on
                    // it, and a drop that writes a position into the log. What it does
                    // not claim is section 12.3's "choose which Bar is being worked
                    // on", which is a shelf chooser over one shelf and would be
                    // furniture until there is a second one.
                    BarPage(),
                    RecipesPage(),
                    // Section 12.3 gives this tab statistics, a consumption curve, value, a
                    // shopping list, devices and sync. Only the value exists, so the page
                    // shows the value and keeps the sentence naming the rest -- replacing
                    // the placeholder outright would claim six features and ship one.
                    CellarPage(),
                    // Section 12.3's fifth tab, asked for by the owner: the application's own
                    // settings, which were a section at the bottom of 记录. Devices and sync stay
                    // there -- see `SettingsPage` for where the line is and why.
                    SettingsPage(),
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
          Copy.tabBar.textFor(locale.primaryTag),
          Copy.tabRecipes.textFor(locale.primaryTag),
          Copy.tabCellar.textFor(locale.primaryTag),
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
