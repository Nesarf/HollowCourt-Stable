import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'display_providers.dart';
import 'theme.dart';

/// Softens a change of world: the outgoing ground closes over the screen and opens again on the new one.
///
/// **This is the owner's instruction of 2026-09-30, and it reverses a rule.** `DESIGN.md` 12.8 said *no motion
/// in the stable build -- not "no motion yet": none*, with the argument that a pressed state is *another
/// drawing* rather than a frame between two, which is why the navigation bar's 90 ms press transition was
/// removed. The owner has asked for this by name since, so the rule is not what it was, and the section is
/// corrected in the same change -- a document that goes on forbidding what the application does is worse than
/// either.
///
/// **What it deliberately is not is a cross-fade between two palettes**, and the first attempt at this was
/// exactly that, which is why the note is here. Fading one world into another passes through mixtures: amber
/// and ivory become a colour that belongs to no world, and the four themes would be described as one drawing
/// with different numbers -- the thing the old rule was protecting, arrived at by a different road. **So the
/// two are never on screen together.** The ground of the world being left closes to full opacity over the
/// screen, and opens again to reveal the new one underneath. The cut is still a cut; it is staged.
///
/// **The ground rather than black or white**, because a world's ground is the colour the screen already was at
/// its edges. Closing in that colour reads as the room darkening rather than as a curtain being dropped.
///
/// **Nothing here holds the interface back.** The new world is built and live on the first frame, so a tap
/// during the fade lands where it would have landed anyway; the veil is decoration and takes nothing.
class ThemeCrossfade extends ConsumerStatefulWidget {
  const ThemeCrossfade({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
  });

  final Widget child;

  /// How long the veil takes to open. Long enough to read as a transition, short enough that a reader who came
  /// here to change a setting is not kept waiting by their own setting.
  final Duration duration;

  @override
  ConsumerState<ThemeCrossfade> createState() => _ThemeCrossfadeState();
}

class _ThemeCrossfadeState extends ConsumerState<ThemeCrossfade> {
  /// The world's ground as it was a moment ago, or null when there is nothing to close over.
  Color? _leaving;

  /// Whether a fade is in flight, so a reader tapping through three themes quickly does not stack veils.
  bool _fading = false;

  @override
  Widget build(BuildContext context) {
    // **Watched, and this is what makes the veil possible at all.** The palette is global state, applied by the
    // root before anything is built, so by the time this widget's `build` runs there is no record of what the
    // screen looked like a moment ago -- unless somebody keeps one. This is that record.
    ref.listen<HollowPaletteValue>(displaySettingsProvider.select((s) => s.theme), (previous, next) {
      if (previous?.name == next.name) return;
      // The ground of the world being LEFT, which is what the screen was painted in.
      _startFade(previous?.ground ?? next.ground);
    });
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_leaving case final colour?)
          IgnorePointer(
            child: TweenAnimationBuilder<double>(
              key: ValueKey<Color>(colour),
              tween: Tween<double>(begin: 1, end: 0),
              duration: widget.duration,
              curve: Curves.easeOutCubic,
              onEnd: () {
                if (!mounted) return;
                setState(() {
                  _leaving = null;
                  _fading = false;
                });
              },
              builder: (context, opacity, _) => Container(
                color: colour.withValues(alpha: opacity.clamp(0.0, 1.0)),
              ),
            ),
          ),
      ],
    );
  }

  void _startFade(Color ground) {
    if (_fading) return;
    _fading = true;
    // A frame's delay, so the veil begins from the frame the world actually changed rather than from the frame
    // the setting was written.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _leaving = ground);
    });
  }
}
