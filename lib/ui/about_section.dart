import 'package:flutter/material.dart';

import 'l10n/dual_copy.dart';
import 'l10n/dual_copy_text.dart';
import 'open_url.dart';
import 'theme.dart';

/// The build this program is: its name, its version, and the source it came from.
///
/// **The two build values are compile-time and default to a word rather than a guess.** They arrive
/// as `--dart-define`s from the packaging scripts, which know the version and can ask git for the
/// commit. A debug run and every test therefore read `unknown`, and that is deliberate: a build that
/// cannot say which source it came from should say so, and a plausible-looking value would be a claim
/// nobody could check.
///
/// **The default was `1.0.0+1` until 2026-09-23, and that was worse than either word.** A version number
/// in the default slot is not a fallback, it is a statement -- so 关于空庭 on **every** build of all three
/// platforms displayed a value that looked like an answer and was a leftover, because the paragraph above
/// claimed a `--dart-define` that **no packaging script passed**. The scripts pass it now (the name is
/// derived from `pubspec` in one place) and the default is the word this comment always promised.
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: 'unknown',
);
const String buildCommit = String.fromEnvironment('BUILD_COMMIT');

/// **Where the source lives, in one place.** The public mirror rather than a private remote: this is the
/// address a reader can actually open, and the one the About screen is for.
const String repositoryUrl = 'https://github.com/Nesarf/HollowCourt-Stable';

/// The name, the version, where it came from, and where to find it.
///
/// **What this screen is for.** A person who has installed something is entitled to know what it
/// claims to be, and the two facts that make a bug report actionable are the version and the commit.
/// It is also where the naming rule and the icon's licence are written down for a reader rather than
/// for a maintainer -- section 0 and section 12.7 respectively, neither of which a user would ever
/// find in the repository.
///
/// **And the repository address goes at the very bottom, after every fact about the build.** It is the last
/// thing on the last section of the settings screen by the owner's instruction, because it is the one line
/// here that leads somewhere else rather than describing what is already in front of the reader.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DualCopyText(Copy.aboutHeading, style: HollowType.heading),
        const SizedBox(height: 10),
        DualCopyText(Copy.aboutWhat, style: HollowType.body),
        const SizedBox(height: 6),
        // The motto directly under the description it belongs to, and the publisher as a row with the rest of
        // the build's own facts.
        Text(Copy.aboutMotto, style: HollowType.caption.copyWith(color: HollowPalette.gold)),
        const SizedBox(height: 16),
        _Row(
          label: Copy.aboutPublisher,
          value: 'S.M.Y.T.',
        ),
        const SizedBox(height: 8),
        _Row(
          label: Copy.aboutVersion,
          value: appVersion,
        ),
        const SizedBox(height: 8),
        _Row(
          label: Copy.aboutCommit,
          // Short, because a full hash is forty characters of noise on a phone; the short form is
          // what `git log --oneline` prints and what a person can paste into a search.
          value: buildCommit.isEmpty
              ? Copy.aboutCommitUnknown
              : buildCommit.substring(0, buildCommit.length < 9 ? buildCommit.length : 9),
        ),
        const SizedBox(height: 18),
        DualCopyText(Copy.aboutNaming, style: HollowType.caption),
        const SizedBox(height: 6),
        DualCopyText(Copy.aboutTypeface, style: HollowType.caption),
        const SizedBox(height: 20),
        const _RepositoryLink(),
      ],
    );
  }
}

/// The repository, at the bottom of the bottom section, and what happens when it cannot be opened.
///
/// **Stateful for one reason: the failure has to be visible.** Tapping either opens the reader's own browser or
/// replaces the hint with the address and the reason, because a link that does nothing when tapped is worse than
/// no link -- the reader cannot tell whether the tap missed, the application is broken, or the address is wrong.
class _RepositoryLink extends StatefulWidget {
  const _RepositoryLink();

  @override
  State<_RepositoryLink> createState() => _RepositoryLinkState();
}

class _RepositoryLinkState extends State<_RepositoryLink> {
  bool _failed = false;

  Future<void> _open() async {
    final opened = await openInBrowser(repositoryUrl);
    if (!mounted) return;
    setState(() => _failed = !opened);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _open,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DualCopyText(Copy.aboutRepository, style: HollowType.body),
                  const SizedBox(width: 6),
                  Icon(Icons.open_in_new, size: 14, color: HollowPalette.gold),
                ],
              ),
              const SizedBox(height: 2),
              DualCopyText(Copy.aboutRepositoryHint, style: HollowType.caption),
            ],
          ),
        ),
        if (_failed) ...[
          const SizedBox(height: 8),
          DualCopyText(
            Copy.aboutRepositoryFailed,
            style: HollowType.caption.copyWith(color: HollowPalette.rose),
          ),
          const SizedBox(height: 4),
          // Selectable, because the point of showing it is that the reader can carry it somewhere else.
          SelectableText(repositoryUrl, style: HollowType.numeric),
        ],
      ],
    );
  }
}

/// A label and its value, right-aligned, the shape the Cellar tab uses for its figures.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final CopyLine label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: DualCopyText(label, style: HollowType.body)),
        const SizedBox(width: 12),
        SelectableText(value, style: HollowType.numeric),
      ],
    );
  }
}
