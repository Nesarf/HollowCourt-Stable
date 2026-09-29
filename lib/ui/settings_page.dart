import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'about_section.dart';
import 'developer_section.dart';
import 'display_section.dart';
import 'names_section.dart';
import 'integrity_section.dart';
import 'l10n/dual_copy_text.dart';
import 'prism.dart';
import 'settings_section.dart';
import 'theme.dart';

/// The Settings tab: what this application is, rather than what is in the cellar.
///
/// **A tab of its own, and it used to be a section inside 记录.** Section 12.3 gave four tabs and no
/// settings one, so the reader's language, measuring system and money lived at the bottom of the
/// Cellar tab, under the statistics -- which is the screen a person opens to look at their bottles,
/// and the wrong place to find the controls for the application itself. The owner asked for a fifth
/// tab by name; this is the screen, and 12.3 now names five.
///
/// **What did not move is 设备与同步.** Devices, sync and the three adapters stay on 记录, because
/// section 12.3 puts them there and because they are facts about *this cellar* -- which Bar is on
/// which device, and what has been exchanged -- rather than about the application. The split is
/// "how the program behaves" against "what has happened to my bottles", and both halves now have a
/// screen that says which it is. [Copy.settingsIntro] is the sentence that draws the line for a
/// reader who guessed wrong.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          DualCopyText(Copy.settingsPageTitle, style: HollowType.heading),
          SizedBox(height: 6),
          DualCopyText(Copy.settingsIntro, style: HollowType.caption),
          SizedBox(height: 24),
          // Each section brings its own heading -- 语言与字幕, 界面样式, the units, the money, the
          // developer tools, the integrity check -- so this page owns the title and the order, and
          // nothing else. A second heading here would be the same sentence twice.
          //
          // THE ORDER IS BY WHO IS LOOKING. Language and interface first, because those are what a
          // reader came here for; then the units and the money, which are choices about their
          // bottles; then the build's own facts, which nobody needs unless something is wrong.
          SettingsSection(),
          // **The gap alone was the whole separation, and a reader said so.** Sections had 32 pixels
          // of nothing between them, which on a dark page is not a boundary. The motif divider is the
          // study's own suggestion for exactly this: a line plus small diamonds, so that the shape a
          // reader already associates with this application is also what tells them where one group ends.
          const SizedBox(height: 20),
          const PrismDivider(size: 8),
          const SizedBox(height: 28),
          // **The names sit here rather than beside the sync controls**, and the owner asked for exactly
          // that: 设置 is where a device says what it is, and 记录 is where an *exchange* is arranged. The
          // sync screen shows the name it is presenting; this is where it is chosen.
          NamesSection(),
          // **The gap alone was the whole separation, and a reader said so.** Sections had 32 pixels
          // of nothing between them, which on a dark page is not a boundary. The motif divider is the
          // study's own suggestion for exactly this: a line plus small diamonds, so that the shape a
          // reader already associates with this application is also what tells them where one group ends.
          const SizedBox(height: 20),
          const PrismDivider(size: 8),
          const SizedBox(height: 28),
          DisplaySection(),
          // **The gap alone was the whole separation, and a reader said so.** Sections had 32 pixels
          // of nothing between them, which on a dark page is not a boundary. The motif divider is the
          // study's own suggestion for exactly this: a line plus small diamonds, so that the shape a
          // reader already associates with this application is also what tells them where one group ends.
          const SizedBox(height: 20),
          const PrismDivider(size: 8),
          const SizedBox(height: 28),
          IntegritySection(),
          // **The gap alone was the whole separation, and a reader said so.** Sections had 32 pixels
          // of nothing between them, which on a dark page is not a boundary. The motif divider is the
          // study's own suggestion for exactly this: a line plus small diamonds, so that the shape a
          // reader already associates with this application is also what tells them where one group ends.
          const SizedBox(height: 20),
          const PrismDivider(size: 8),
          const SizedBox(height: 28),
          DeveloperSection(),
          // **And then the last thing on the page, by the owner's instruction: 关于空庭, always at the
          // bottom.** It is where the repository address lives, and an address that leads out of the
          // application belongs after everything that describes what is already in it. Moved here from
          // between the interface and the integrity check, which is where it used to sit.
          const SizedBox(height: 20),
          const PrismDivider(size: 8),
          const SizedBox(height: 28),
          AboutSection(),
        ],
      ),
    );
  }
}
