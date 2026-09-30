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

/// **Where the author is, in one place, for the same reason the source address is.**
///
/// Given by the owner on 2026-09-30, and the first of them replaced a donation link within the hour. **That
/// replacement was not cosmetic.** PCL -- the licence covering the two pieces in `art/` -- forbids collecting
/// compensation of any kind, under any name, even where the use is not for profit (第3条第2項第1号: 「非営利目的で
/// あっても、あらゆる名目の対価を徴収しまたは報酬を受けてはならない」). A donation link attached to a work that
/// contains that artwork asks for exactly that; a profile link on any of these three sites does not, because
/// nothing flows from the work to the author. **So the heading says 作者 and not 支持**, and that is the whole
/// point of the change.
///
/// **Three sites and not one, because the author is on all three and none of them is a substitute for another.**
/// bilibili published the work, 网易云音乐 distributes the music, SoundCloud holds the same music in the place
/// that reaches outside China. A row that showed only one would be answering a question the reader did not ask.
///
/// They are constants rather than literals in the widget so each address appears once in the codebase -- the
/// argument the source address above makes, and the one that put the version and the commit behind a `--dart-define`.
const String bilibiliUrl = 'https://space.bilibili.com/11247581';
const String neteaseUrl = 'https://music.163.com/#/artist?id=37459218';
const String soundcloudUrl = 'https://soundcloud.com/nesarfmollor';

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
        const SizedBox(height: 14),
        // **The PCL credit, and it is selectable rather than plain text.** A credit exists to name a rights
        // holder, so a reader who wants to check or reuse it has to be able to copy it -- the same reason the
        // address under a failed link is selectable. It sits above the source link so that "what this is" finishes
        // before "where to find it" begins.
        SelectableText(
          Copy.aboutCharacterCredit,
          style: HollowType.caption.copyWith(color: HollowPalette.inkFaint, height: 1.5),
        ),
        const SizedBox(height: 20),
        const _ExternalLink(
          label: Copy.aboutRepository,
          hint: Copy.aboutRepositoryHint,
          failed: Copy.aboutRepositoryFailed,
          url: repositoryUrl,
        ),
        const SizedBox(height: 16),
        // **Three rows under one heading, and the heading carries the meaning.** 作者 is a fact about the person
        // rather than a request to the reader, which is the constraint PCL's 第3条第2項第1号 imposes on any work
        // carrying the artwork in `art/` -- see the constants above. The first row carries the heading and the two
        // below it are the same kind of thing, so only the first has a line above it.
        //
        // No sentence under them: bilibili, 网易云音乐 and SoundCloud each name themselves, and a line explaining
        // what a music profile is would be the interface telling a reader something they already know.
        const _ExternalLink(
          label: Copy.aboutAuthor,
          hint: null,
          failed: Copy.aboutSupportFailed,
          url: bilibiliUrl,
        ),
        const SizedBox(height: 10),
        const _ExternalLink(
          label: Copy.aboutNetease,
          hint: null,
          failed: Copy.aboutSupportFailed,
          url: neteaseUrl,
        ),
        const SizedBox(height: 10),
        const _ExternalLink(
          label: Copy.aboutSoundcloud,
          hint: null,
          failed: Copy.aboutSupportFailed,
          url: soundcloudUrl,
        ),
      ],
    );
  }
}

/// A row that opens an address, and what happens when it cannot be opened.
///
/// **Stateful for one reason: the failure has to be visible.** Tapping opens the reader's own browser, or replaces
/// the hint with the address and the reason -- because a link that does nothing when tapped is worse than no link:
/// the reader cannot tell whether the tap missed, the application is broken, or the address is wrong.
///
/// **Two callers, one widget.** The source row and the support row are the same thing with different words, and the
/// alternative -- a second copy of this state machine -- is how the two would drift apart in behaviour, which is the
/// one thing a reader would never notice until one of them broke.
class _ExternalLink extends StatefulWidget {
  const _ExternalLink({
    required this.label,
    required this.hint,
    required this.failed,
    required this.url,
  });

  /// The link's own name, in the reader's language.
  final CopyLine label;

  /// What opening it does, or null when the name is enough -- the support row has no hint, because the sentence
  /// above it already says what it is for.
  final CopyLine? hint;

  /// Shown when no browser could be reached, followed by the address so it can be carried elsewhere.
  final CopyLine failed;

  final String url;

  @override
  State<_ExternalLink> createState() => _ExternalLinkState();
}

class _ExternalLinkState extends State<_ExternalLink> {
  bool _failed = false;

  Future<void> _open() async {
    final opened = await openInBrowser(widget.url);
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // **Flexible, and this is the same fault the shopping list had.** A `Text` in a `Row` with no
                  // flex takes its full intrinsic width, so a label longer than the screen overflows instead of
                  // wrapping -- and `_ShoppingRows` records the identical fix for the identical reason. Measured:
                  // at 200 px the row overflowed by 115 px before this, and 240 px was the narrowest that fitted
                  // by luck rather than by design.
                  //
                  // `crossAxisAlignment.start` on both the Row and the text keeps the icon against the first line
                  // rather than centred on a two-line label, which is where an eye looks for it.
                  Flexible(child: DualCopyText(widget.label, style: HollowType.body)),
                  const SizedBox(width: 6),
                  Icon(Icons.open_in_new, size: 14, color: HollowPalette.gold),
                ],
              ),
              if (widget.hint case final hint?) ...[
                const SizedBox(height: 2),
                DualCopyText(hint, style: HollowType.caption),
              ],
            ],
          ),
        ),
        if (_failed) ...[
          const SizedBox(height: 8),
          DualCopyText(
            widget.failed,
            style: HollowType.caption.copyWith(color: HollowPalette.rose),
          ),
          const SizedBox(height: 4),
          // Selectable, because the point of showing it is that the reader can carry it somewhere else.
          SelectableText(widget.url, style: HollowType.numeric),
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
